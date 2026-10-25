import AppKit

@MainActor
final class CameraBubble {
    private let panel: NSPanel
    private let preview: CameraPreview
    private var bubbleFrame: NSRect
    private var screen: NSScreen?
    private let style: BubbleStyle
    var onDoubleClick: (() -> Void)? {
        get { preview.onDoubleClick }
        set { preview.onDoubleClick = newValue }
    }

    static var mainScreen: NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value == CGMainDisplayID()
        }
    }

    init(renderer: CameraRenderer, style: BubbleStyle) {
        self.style = style
        let screen = Self.mainScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 800)
        bubbleFrame = NSRect(x: screen.minX + 24, y: screen.minY + 24, width: 240, height: 240)
        panel = NSPanel(contentRect: bubbleFrame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        preview = CameraPreview(renderer: renderer)
        panel.contentView = preview
        style.onChange = { [weak self] in self?.updateStyle() }
        preview.onDrag = { [weak self] delta in self?.drag(by: delta) }
        updateStyle()
    }

    private func drag(by delta: NSSize) {
        guard let screen = screen ?? Self.mainScreen else { return }
        var frame = panel.frame
        frame.origin.x += delta.width
        frame.origin.y += delta.height
        bubbleFrame = constrained(frame, to: screen)
        panel.setFrame(bubbleFrame, display: true)
    }

    func move(to screen: NSScreen) {
        if self.screen?.displayID != screen.displayID {
            bubbleFrame.origin = NSPoint(x: screen.visibleFrame.minX + 24, y: screen.visibleFrame.minY + 24)
        }
        self.screen = screen
        bubbleFrame = constrained(bubbleFrame, to: screen)
        panel.setFrame(preview.fullScreen ? screen.frame : bubbleFrame, display: true)
    }

    private func updateStyle() {
        let frame = preview.fullScreen ? bubbleFrame : panel.frame
        let dimensions = style.shape.dimensions(for: style.size)
        bubbleFrame = NSRect(x: frame.midX - dimensions.width / 2, y: frame.midY - dimensions.height / 2,
                             width: dimensions.width, height: dimensions.height)
        if let screen = screen ?? Self.mainScreen ?? panel.screen {
            bubbleFrame = constrained(bubbleFrame, to: screen)
        }
        preview.apply(shape: style.shape, filter: style.filter)
        if !preview.fullScreen { panel.setFrame(bubbleFrame, display: true) }
    }

    private func constrained(_ frame: NSRect, to screen: NSScreen) -> NSRect {
        var frame = frame
        let bounds = screen.frame
        frame.size.width = min(frame.width, bounds.width)
        frame.size.height = min(frame.height, bounds.height)
        frame.origin.x = max(bounds.minX, min(frame.minX, bounds.maxX - frame.width))
        frame.origin.y = max(bounds.minY, min(frame.minY, bounds.maxY - frame.height))
        return frame
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func hide() {
        setFullScreen(false)
        panel.orderOut(nil)
    }

    func setFullScreen(_ enabled: Bool) {
        guard enabled != preview.fullScreen else { return }
        if enabled { bubbleFrame = panel.frame }
        if let screen = screen ?? Self.mainScreen ?? panel.screen {
            bubbleFrame = constrained(bubbleFrame, to: screen)
        }
        preview.fullScreen = enabled
        // Above the menu bar and Dock so full-screen me fills the whole recording.
        panel.level = enabled ? NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1) : .floating
        let target = enabled ? (screen?.frame ?? panel.screen?.frame ?? bubbleFrame) : bubbleFrame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().setFrame(target, display: true)
        }
    }
}

