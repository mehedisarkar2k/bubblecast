import AVFoundation
import OSLog

// Automatic level for a voice. Speech is lifted towards a podcast-like level, but never so far that the
// room noise under it becomes loud, and pauses are turned down so the boost does not bring up hiss or fans.
final class SpeechGain {
    private let targetDB: Float = -13
    private let maxGainDB: Float = 18
    // Room noise may sit at most this loud after the boost.
    private let noiseCeilingDB: Float = -50
    private let pauseCutDB: Float = -12
    private var gainDB: Float = 0
    private var gateDB: Float = 0
    private var noiseFloorDB: Float = -60
    private var holdBuffers = 0
    private var loggedError = false
    private let logger = Logger(subsystem: "io.github.mehedisarkar2k.bubblecast", category: "SpeechGain")

    func apply(to buffer: CMSampleBuffer) {
        guard let format = buffer.formatDescription?.audioStreamBasicDescription,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 else { return }
        do {
            try buffer.withAudioBufferList { list, _ in
                let channels = list.compactMap { channel -> UnsafeMutableBufferPointer<Float>? in
                    guard let data = channel.mData else { return nil }
                    return UnsafeMutableBufferPointer(start: data.assumingMemoryBound(to: Float.self),
                                                      count: Int(channel.mDataByteSize) / MemoryLayout<Float>.size)
                }
                update(levelDB: Self.levelDB(of: channels))
                let linear = powf(10, (gainDB + gateDB) / 20)
                for samples in channels {
                    for index in samples.indices { samples[index] = Self.limit(samples[index] * linear) }
                }
            }
        } catch {
            guard !loggedError else { return }
            loggedError = true
            logger.error("Audio level skipped: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func update(levelDB: Float) {
        // The noise floor follows quiet moments down quickly and drifts up slowly, so speech never raises it.
        noiseFloorDB += levelDB < noiseFloorDB ? max(-1, levelDB - noiseFloorDB) : 0.02
        let speaking = levelDB > noiseFloorDB + 10
        if speaking {
            holdBuffers = 8
            let limit = min(maxGainDB, max(noiseCeilingDB - noiseFloorDB, 0))
            let wanted = min(max(targetDB - levelDB, 0), limit)
            // Rises slowly so breaths are not pumped up, falls fast so loud words do not distort.
            gainDB += wanted > gainDB ? min(0.1, wanted - gainDB) : max(-1, wanted - gainDB)
        } else if holdBuffers > 0 {
            holdBuffers -= 1
        }
        // The pause cut opens fast for the first syllable and closes gently after a short hold.
        let gateTarget = speaking || holdBuffers > 0 ? 0 : pauseCutDB
        gateDB += gateTarget > gateDB ? min(3, gateTarget - gateDB) : max(-1, gateTarget - gateDB)
    }

    private static func levelDB(of channels: [UnsafeMutableBufferPointer<Float>]) -> Float {
        var sum: Float = 0
        var count = 0
        for samples in channels {
            for sample in samples { sum += sample * sample }
            count += samples.count
        }
        guard count > 0, sum > 0 else { return -120 }
        return 10 * log10f(sum / Float(count))
    }

    private static func limit(_ sample: Float) -> Float {
        let knee: Float = 0.8
        let size = abs(sample)
        guard size > knee else { return sample }
        let limited = knee + (1 - knee) * tanhf((size - knee) / (1 - knee))
        return sample < 0 ? -limited : limited
    }
}
