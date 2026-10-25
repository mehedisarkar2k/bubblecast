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
        let size = style.shape.dimensions(for: style.size)
        bubbleFrame = Self.mainScreen.map { Self.savedFrame(size, on: $0) } ?? NSRect(origin: .zero, size: size)
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
        Self.savePosition(of: bubbleFrame, on: screen)
    }

    func move(to screen: NSScreen) {
        self.screen = screen
        bubbleFrame = Self.savedFrame(bubbleFrame.size, on: screen)
        panel.setFrame(preview.fullScreen ? screen.frame : bubbleFrame, display: true)
    }

    private func updateStyle() {
        let dimensions = style.shape.dimensions(for: style.size)
        if let screen = screen ?? Self.mainScreen ?? panel.screen {
            bubbleFrame = Self.savedFrame(dimensions, on: screen)
        } else {
            bubbleFrame.size = dimensions
        }
        preview.apply(shape: style.shape, filter: style.filter)
        if !preview.fullScreen { panel.setFrame(bubbleFrame, display: true) }
    }

    // The position is saved as a fraction of the screen's free area, so it stays in the same corner after
    // a size change, a resolution change or a move to another screen. The default is bottom-right.
    private static func savedFrame(_ size: NSSize, on screen: NSScreen) -> NSRect {
        let area = screen.visibleFrame.insetBy(dx: 24, dy: 24)
        let defaults = UserDefaults.standard
        let x = defaults.object(forKey: "bubble.positionX") as? Double ?? 1
        let y = defaults.object(forKey: "bubble.positionY") as? Double ?? 0
        return NSRect(x: area.minX + max(area.width - size.width, 0) * x,
                      y: area.minY + max(area.height - size.height, 0) * y,
                      width: size.width, height: size.height)
    }

    private static func savePosition(of frame: NSRect, on screen: NSScreen) {
        let area = screen.visibleFrame.insetBy(dx: 24, dy: 24)
        let fraction = { (offset: CGFloat, room: CGFloat) -> Double in
            room > 0 ? Double(min(max(offset / room, 0), 1)) : 0
        }
        UserDefaults.standard.set(fraction(frame.minX - area.minX, area.width - frame.width), forKey: "bubble.positionX")
        UserDefaults.standard.set(fraction(frame.minY - area.minY, area.height - frame.height), forKey: "bubble.positionY")
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

