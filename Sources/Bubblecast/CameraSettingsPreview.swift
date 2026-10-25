import AppKit
import QuartzCore
import SwiftUI

@MainActor
struct CameraSettingsPreview: NSViewRepresentable {
    let renderer: CameraRenderer

    func makeNSView(context: Context) -> PreviewView { PreviewView(renderer: renderer) }
    func updateNSView(_ nsView: PreviewView, context: Context) {}
    static func dismantleNSView(_ nsView: PreviewView, coordinator: ()) { nsView.detach() }

    @MainActor
    final class PreviewView: NSView {
        private let renderer: CameraRenderer
        private let target = CAMetalLayer()

        init(renderer: CameraRenderer) {
            self.renderer = renderer
            super.init(frame: .zero)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
            layer?.cornerRadius = 12
            layer?.masksToBounds = true
            layer?.addSublayer(target)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

        func detach() { renderer.removeTarget(target) }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { detach() } else { renderer.addTarget(target) }
            needsLayout = true
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            needsLayout = true
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            renderer.layout(bounds: bounds, scale: window?.backingScaleFactor ?? 1, target: target)
            CATransaction.commit()
        }
    }
}
