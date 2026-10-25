import AppKit
import AVFoundation
import ScreenCaptureKit

@MainActor
final class ScreenRecorder: NSObject, SCStreamDelegate {
    var onStarted: (() -> Void)?
    var onFinished: ((URL) -> Void)?
    var onError: ((Error) -> Void)?
    private var stream: SCStream?
    private var writer: MovieWriter?
    private var destination: URL?

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
        // The encoder needs even dimensions; rounding down also avoids upscaling.
        configuration.width = max(2, Int(width * scale) / 2 * 2)
        configuration.height = max(2, Int(height * scale) / 2 * 2)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.showsCursor = true
        configuration.capturesAudio = false
        configuration.captureMicrophone = microphoneID != nil
        configuration.microphoneCaptureDeviceID = microphoneID
        let destination = try RecordingPaths.nextFile()
        // Record to a local temporary file and move it at the end, so a synced folder (Google Drive)
        // never uploads a half-written video.
        let writer = try MovieWriter(url: RecordingPaths.temporaryFile(), width: configuration.width,
                                     height: configuration.height, withAudio: microphoneID != nil)
        writer.onFirstFrame = { [weak self] in
            Task { @MainActor [weak self] in self?.onStarted?() }
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(writer, type: .screen, sampleHandlerQueue: writer.queue)
        if microphoneID != nil {
            try stream.addStreamOutput(writer, type: .microphone, sampleHandlerQueue: writer.queue)
        }
        self.stream = stream
        self.writer = writer
        self.destination = destination
        do {
            try await stream.startCapture()
        } catch {
            // A delegate failure may already have reported this error.
            if self.stream != nil {
                writer.cancel()
                clear()
                throw error
            }
        }
    }

    func stop() async {
        guard let stream, let writer, let destination else { return }
        do {
            try await stream.stopCapture()
            try await writer.finish()
            let saved = try RecordingPaths.save(writer.url, to: destination)
            clear()
            onFinished?(saved)
        } catch {
            writer.cancel()
            clear()
            onError?(error)
        }
    }

    private func clear() {
        stream = nil
        writer = nil
        destination = nil
    }

    private func fail(_ error: Error) async {
        guard let stream else { return }
        writer?.cancel()
        clear()
        do {
            try await stream.stopCapture()
        } catch let cleanupError {
            onError?(AppError.message("\(error.localizedDescription)\nStopping the failed stream also failed: \(cleanupError.localizedDescription)"))
            return
        }
        onError?(error)
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let id = ObjectIdentifier(stream)
        Task { @MainActor [weak self] in
            guard let self, let current = self.stream, ObjectIdentifier(current) == id else { return }
            await fail(error)
        }
    }
}
