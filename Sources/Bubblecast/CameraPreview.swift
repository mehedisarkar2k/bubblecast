import AppKit

@MainActor
final class CameraPreview: NSView {
    private let renderer: CameraRenderer
    private var shape = BubbleShape.circle
    var fullScreen = false { didSet { needsLayout = true } }
    var onDrag: ((NSSize) -> Void)?
    var onDoubleClick: (() -> Void)?
    // Dragging is handled here because window-background dragging would swallow double-clicks.
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick?() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !fullScreen else { return }
        onDrag?(NSSize(width: event.deltaX, height: -event.deltaY))
    }

    init(renderer: CameraRenderer) {
        self.renderer = renderer
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        layer?.addSublayer(renderer.layer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    func apply(shape: BubbleShape, filter: BubbleFilter) {
        self.shape = shape
        renderer.setFilter(filter)
        needsLayout = true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeScreenNotification, object: window)
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
                name: NSWindow.didChangeScreenNotification, object: window)
        }
        needsLayout = true
    }

    @objc private func screenChanged(_ notification: Notification) { needsLayout = true }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        renderer.layout(bounds: bounds, scale: window?.backingScaleFactor ?? 1)
        layer?.cornerRadius = fullScreen ? 0 : shape.cornerRadius(in: bounds)
        layer?.borderWidth = fullScreen ? 0 : 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        CATransaction.commit()
    }
}
