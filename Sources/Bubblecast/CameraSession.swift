import AVFoundation

// The session's configuration and start/stop operations are confined to this queue.
final class CameraSession: @unchecked Sendable {
    let session = AVCaptureSession()
    let renderer = CameraRenderer()
    private let output = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "io.github.mehedisarkar2k.bubblecast.camera.video")
    private let queue = DispatchQueue(label: "io.github.mehedisarkar2k.bubblecast.camera")
    private var deviceID: String?

    func start(deviceID: String) async throws {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            throw AppError.message("Allow camera access for Bubblecast in System Settings → Privacy & Security → Camera.")
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    try renderer.validate()
                    if session.outputs.isEmpty {
                        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
                        output.alwaysDiscardsLateVideoFrames = true
                        output.setSampleBufferDelegate(renderer, queue: videoQueue)
                        guard session.canAddOutput(output) else {
                            throw AppError.message("The camera video output could not be added.")
                        }
                        session.addOutput(output)
                    }
                    if self.deviceID != deviceID {
                        guard let device = AVCaptureDevice(uniqueID: deviceID) else {
                            throw AppError.message("No camera is available.")
                        }
                        let input = try AVCaptureDeviceInput(device: device)
                        session.beginConfiguration()
                        defer { session.commitConfiguration() }
                        session.sessionPreset = .high
                        let oldInputs = session.inputs
                        for old in oldInputs { session.removeInput(old) }
                        guard session.canAddInput(input) else {
                            for old in oldInputs where session.canAddInput(old) { session.addInput(old) }
                            throw AppError.message("The camera could not be added to the capture session.")
                        }
                        session.addInput(input)
                        self.deviceID = deviceID
                    }
                    if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = false
                    }
                    session.startRunning()
                    guard session.isRunning else {
                        throw AppError.message("The camera could not start. Check that it is connected and available.")
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        queue.async { [self] in session.stopRunning() }
    }
}
