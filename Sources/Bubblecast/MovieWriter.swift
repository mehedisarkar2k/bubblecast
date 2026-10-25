import AVFoundation
import OSLog
import ScreenCaptureKit

// Writes screen frames and microphone audio to an MP4. Every append and the final flush run on `queue`,
// the same serial queue ScreenCaptureKit delivers samples on.
final class MovieWriter: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "io.github.mehedisarkar2k.bubblecast.writer")
    let url: URL
    var onFirstFrame: (@Sendable () -> Void)?
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let audio: AVAssetWriterInput?
    private let gain = SpeechGain()
    private var started = false
    private var lastTime = CMTime.invalid
    private var failure: Error?
    private let logger = Logger(subsystem: "io.github.mehedisarkar2k.bubblecast", category: "MovieWriter")

    init(url: URL, width: Int, height: Int, withAudio: Bool) throws {
        self.url = url
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        // HEVC at a fixed average bitrate: screen content and a talking head stay sharp at a fraction of the size.
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 3_500_000,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 60,
            ],
        ])
        video.expectsMediaDataInRealTime = true
        writer.add(video)
        if withAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000,
            ])
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            audio = input
        } else {
            audio = nil
        }
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard failure == nil, buffer.isValid else { return }
        switch type {
        case .screen:
            guard Self.isCompleteFrame(buffer) else { return }
            if !started {
                guard writer.startWriting() else {
                    fail(writer.error ?? AppError.message("The video file could not be started."))
                    return
                }
                writer.startSession(atSourceTime: buffer.presentationTimeStamp)
                started = true
                onFirstFrame?()
            }
            append(buffer, to: video)
        case .microphone:
            guard started, let audio else { return }
            gain.apply(to: buffer)
            append(buffer, to: audio)
        default:
            break
        }
    }

    // Runs after capture has stopped; hopping onto the queue lets already delivered samples finish first.
    func finish() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                if let failure { return continuation.resume(throwing: failure) }
                guard started else {
                    return continuation.resume(throwing: AppError.message("No video frames were recorded."))
                }
                video.markAsFinished()
                audio?.markAsFinished()
                if lastTime.isValid { writer.endSession(atSourceTime: lastTime) }
                writer.finishWriting { [self] in
                    if writer.status == .completed {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: writer.error ?? AppError.message("The video file could not be finished."))
                    }
                }
            }
        }
    }

    func cancel() {
        queue.async { [self] in
            if writer.status == .writing { writer.cancelWriting() }
        }
    }

    private func append(_ buffer: CMSampleBuffer, to input: AVAssetWriterInput) {
        // Real-time inputs drop a sample when the encoder is busy rather than stall the capture.
        guard input.isReadyForMoreMediaData else { return }
        guard input.append(buffer) else {
            fail(writer.error ?? AppError.message("A sample could not be written."))
            return
        }
        let end = buffer.presentationTimeStamp + buffer.duration
        let time = end.isValid ? end : buffer.presentationTimeStamp
        if !lastTime.isValid || time > lastTime { lastTime = time }
    }

    private func fail(_ error: Error) {
        guard failure == nil else { return }
        failure = error
        logger.error("\(error.localizedDescription, privacy: .public)")
    }

    private static func isCompleteFrame(_ buffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }
}
