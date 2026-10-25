import AppKit
import AVFoundation
import ScreenCaptureKit

@MainActor
final class ScreenRecorder: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    var onStarted: (() -> Void)?
    var onFinished: ((URL) -> Void)?
    var onError: ((Error) -> Void)?
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var file: URL?

    func start(displayID: CGDirectDisplayID, microphoneID: String?, excluding windowID: CGWindowID) async throws {
        if microphoneID != nil {
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                throw AppError.message("Allow microphone access for Bubblecast in System Settings → Privacy & Security → Microphone.")
            }
        }
        // CGPreflightScreenCaptureAccess can report false after access was granted, so ask ScreenCaptureKit itself.
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw AppError.message("Screen recording is not allowed yet. Open the Bubblecast menu-bar icon → Permissions… and click Allow.\n\n(\(error.localizedDescription))")
        }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw AppError.message("The selected display could not be found.")
        }
        guard let panel = content.windows.first(where: { $0.windowID == windowID }) else {
            throw AppError.message("The control panel could not be excluded from capture. Show the panel and try again.")
        }
        let filter = SCContentFilter(display: display, excludingWindows: [panel])
        let width = Double(display.width) * Double(filter.pointPixelScale)
        let height = Double(display.height) * Double(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        let scale = min(1, 1920.0 / max(width, height))
        // H.264 requires even dimensions; rounding down also avoids upscaling.
        configuration.width = max(2, Int(width * scale) / 2 * 2)
        configuration.height = max(2, Int(height * scale) / 2 * 2)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.showsCursor = true
        configuration.capturesAudio = false
        configuration.captureMicrophone = microphoneID != nil
        configuration.microphoneCaptureDeviceID = microphoneID
        let url = try RecordingPaths.nextFile()
        let recording = SCRecordingOutputConfiguration()
        recording.outputURL = url
        recording.videoCodecType = .h264
        recording.outputFileType = .mp4
        let output = SCRecordingOutput(configuration: recording, delegate: self)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addRecordingOutput(output)
        self.stream = stream
        self.output = output
        file = url
        do {
            try await stream.startCapture()
        } catch {
            // A delegate failure may already have reported this error.
            if self.stream != nil {
                clear()
                throw error
            }
        }
    }

    func stop() async {
        guard let stream else { return }
        do {
            // The output delegate signals when the MP4 has actually been finalized.
            try await stream.stopCapture()
        } catch {
            await fail(error)
        }
    }

    private func clear() {
        stream = nil
        output = nil
        file = nil
    }

    private func fail(_ error: Error) async {
        guard let stream else { return }
        clear()
        do {
            try await stream.stopCapture()
        } catch let cleanupError {
            onError?(AppError.message("\(error.localizedDescription)\nStopping the failed stream also failed: \(cleanupError.localizedDescription)"))
            return
        }
        onError?(error)
    }

    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        let id = ObjectIdentifier(recordingOutput)
        Task { @MainActor [weak self] in
            guard let self, let output, ObjectIdentifier(output) == id else { return }
            onStarted?()
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        let id = ObjectIdentifier(recordingOutput)
        Task { @MainActor [weak self] in
            guard let self, let output, ObjectIdentifier(output) == id, let file else { return }
            clear()
            onFinished?(file)
        }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        let id = ObjectIdentifier(recordingOutput)
        Task { @MainActor [weak self] in
            guard let self, let output, ObjectIdentifier(output) == id else { return }
            await fail(error)
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let id = ObjectIdentifier(stream)
        Task { @MainActor [weak self] in
            guard let self, let current = self.stream, ObjectIdentifier(current) == id else { return }
            await fail(error)
        }
    }
}
