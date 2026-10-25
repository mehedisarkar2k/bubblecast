import AVFoundation
import CoreImage
import Metal
import QuartzCore
import OSLog

// Filters and the shared texture belong to the serial video queue; targets and settings use the lock.
final class CameraRenderer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let layer = CAMetalLayer()
    private let context: CIContext?
    private let commandQueue: (any MTLCommandQueue)?
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let lock = NSLock()
    private var targets: [CAMetalLayer] = []
    private var filter = BubbleFilter.none
    private var loggedError = false
    private var appliedFilter: BubbleFilter?
    private var filters: [CIFilter] = []
    private var sharedTexture: (any MTLTexture)?
    private let logger = Logger(subsystem: "io.github.mehedisarkar2k.bubblecast", category: "CameraRenderer")

    override init() {
        let device = MTLCreateSystemDefaultDevice()
        context = device.map { CIContext(mtlDevice: $0, options: [.cacheIntermediates: false]) }
        commandQueue = device?.makeCommandQueue()
        super.init()
        configure(layer)
        targets = [layer]
    }

    private func configure(_ target: CAMetalLayer) {
        target.device = commandQueue?.device
        target.pixelFormat = .bgra8Unorm
        target.framebufferOnly = false
        target.isOpaque = true
        target.colorspace = colorSpace
        target.maximumDrawableCount = 2
        target.allowsNextDrawableTimeout = true
    }

    func validate() throws {
        guard context != nil, commandQueue != nil else {
            throw AppError.message("Metal is unavailable for the camera preview.")
        }
    }

    @MainActor
    func addTarget(_ target: CAMetalLayer) {
        configure(target)
        lock.withLock {
            if !targets.contains(where: { $0 === target }) { targets.append(target) }
        }
    }

    @MainActor
    func removeTarget(_ target: CAMetalLayer) {
        lock.withLock { targets.removeAll { $0 === target } }
    }

    @MainActor
    func layout(bounds: CGRect, scale: CGFloat, target: CAMetalLayer? = nil) {
        let target = target ?? layer
        lock.withLock {
            target.frame = bounds
            target.contentsScale = scale
            target.drawableSize = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        }
    }

    @MainActor
    func setFilter(_ filter: BubbleFilter) {
        lock.withLock { self.filter = filter }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        autoreleasepool {
            let (targets, selectedFilter) = lock.withLock {
                (self.targets.filter { $0.drawableSize.width > 0 && $0.drawableSize.height > 0 }, filter)
            }
            guard !targets.isEmpty, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer),
                  let context, let commandQueue else { return }
            guard let commands = commandQueue.makeCommandBuffer() else {
                logOnce("Could not create a camera rendering command buffer.")
                return
            }
            if appliedFilter != selectedFilter {
                filters = selectedFilter.makeFilters()
                appliedFilter = selectedFilter
            }
            var image = CIImage(cvPixelBuffer: buffer)
            image = image.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: image.extent.maxX, ty: 0))
            for filter in filters {
                filter.setValue(image, forKey: kCIInputImageKey)
                guard let result = filter.outputImage else {
                    logOnce("A camera filter failed to produce an image.")
                    return
                }
                image = result
            }
            // Materialize the filter graph once when two previews need different aspect-fill crops.
            if targets.count > 1 {
                let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
                if sharedTexture?.width != width || sharedTexture?.height != height {
                    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                        pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
                    descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
                    sharedTexture = commandQueue.device.makeTexture(descriptor: descriptor)
                }
                guard let sharedTexture else { logOnce("Could not allocate the shared camera texture."); return }
                context.render(image, to: sharedTexture, commandBuffer: commands, bounds: image.extent, colorSpace: colorSpace)
                guard let processed = CIImage(mtlTexture: sharedTexture, options: [.colorSpace: colorSpace]) else {
                    logOnce("Could not read the shared camera texture.")
                    return
                }
                image = processed
            } else {
                sharedTexture = nil
            }
            for target in targets {
                guard let drawable = target.nextDrawable() else { continue }
                let bounds = CGRect(x: 0, y: 0, width: drawable.texture.width, height: drawable.texture.height)
                let scale = max(bounds.width / image.extent.width, bounds.height / image.extent.height)
                var fitted = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                fitted = fitted.transformed(by: CGAffineTransform(translationX: bounds.midX - fitted.extent.midX,
                                                                  y: bounds.midY - fitted.extent.midY)).cropped(to: bounds)
                let destination = CIRenderDestination(mtlTexture: drawable.texture, commandBuffer: commands)
                destination.colorSpace = colorSpace
                destination.isFlipped = true
                do {
                    _ = try context.startTask(toRender: fitted, to: destination)
                    commands.present(drawable)
                } catch { logOnce(error.localizedDescription) }
            }
            commands.addCompletedHandler { [self] completed in
                if let error = completed.error { logOnce(error.localizedDescription) }
            }
            commands.commit()
        }
    }

    private func logOnce(_ message: String) {
        let shouldLog = lock.withLock {
            if loggedError { return false }
            loggedError = true
            return true
        }
        if shouldLog { logger.error("\(message, privacy: .public)") }
    }
}
