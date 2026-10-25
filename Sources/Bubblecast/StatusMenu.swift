import AppKit

@MainActor
final class StatusMenu: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let showBar: () -> Void
    private let showPermissions: () -> Void
    private let onError: (Error) -> Void

    init(showBar: @escaping () -> Void, showPermissions: @escaping () -> Void, onError: @escaping (Error) -> Void) {
        self.showBar = showBar
        self.showPermissions = showPermissions
        self.onError = onError
        super.init()
        let menu = NSMenu()
        for (title, action) in [("Show bar", #selector(show)),
                                ("Permissions…", #selector(permissions)),
                                ("Open recordings folder", #selector(openFolder)),
                                ("Quit", #selector(quit))] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            menu.addItem(entry)
        }
        item.menu = menu
        update(recording: false)
    }

    func update(recording: Bool) {
        item.button?.image = Self.icon(recording: recording)
        item.button?.setAccessibilityLabel(recording ? "Bubblecast, recording" : "Bubblecast")
    }

    // A small version of the app icon: a screen with the camera bubble, plus a record dot that turns red.
    private static func icon(recording: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { _ in
            let ink = NSColor.labelColor
            let screen = NSBezierPath(roundedRect: NSRect(x: 3.5, y: 3.5, width: 15.5, height: 11), xRadius: 2.5, yRadius: 2.5)
            screen.lineWidth = 1.5
            ink.setStroke()
            screen.stroke()
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 10, height: 10)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            ink.setFill()
            NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 8, height: 8)).fill()
            (recording ? NSColor.systemRed : ink).setFill()
            NSBezierPath(ovalIn: NSRect(x: 12.5, y: 8, width: 4, height: 4)).fill()
            return true
        }
        image.isTemplate = !recording
        return image
    }

    @objc private func show() { showBar() }
    @objc private func permissions() { showPermissions() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }

    @objc private func openFolder() {
        do {
            try FileManager.default.createDirectory(at: RecordingPaths.root, withIntermediateDirectories: true)
            guard NSWorkspace.shared.open(RecordingPaths.root) else {
                throw AppError.message("The recordings folder could not be opened in Finder.")
            }
        } catch { onError(error) }
    }
}
