import AppKit
import AVFoundation
import SwiftUI

@MainActor
final class CameraSettingsPanel {
    private let window: NSPanel
    private let style: BubbleStyle
    private let renderer: CameraRenderer
    private var localMonitor: Any?
    private var globalMonitor: Any?

    init(style: BubbleStyle, renderer: CameraRenderer) {
        self.style = style
        self.renderer = renderer
        window = SettingsWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func toggle(above bar: NSWindow) {
        if window.isVisible { close(); return }
        let content = NSHostingView(rootView: SettingsView(style: style, renderer: renderer))
        window.contentView = content
        let size = content.fittingSize
        let screen = bar.screen?.visibleFrame ?? bar.frame
        let x = max(screen.minX, min(bar.frame.midX - size.width / 2, screen.maxX - size.width))
        let y = max(screen.minY, min(bar.frame.maxY + 10, screen.maxY - size.height))
        window.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
        window.level = NSWindow.Level(rawValue: bar.level.rawValue + 1)
        window.makeKeyAndOrderFront(nil)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp, .otherMouseUp, .keyDown]) {
            [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { close(); return nil }
            } else if !window.frame.contains(NSEvent.mouseLocation) {
                // Let the bar's button toggle first so its click cannot close and immediately reopen the popup.
                Task { @MainActor [weak self] in self?.close() }
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) {
            [weak self] _ in
            Task { @MainActor [weak self] in self?.close() }
        }
    }

    func close() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        window.orderOut(nil)
        // Releasing the hosting view also detaches its Metal target while the popup is closed.
        window.contentView = nil
    }
}

@MainActor
private final class SettingsWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
private struct SettingsView: View {
    @ObservedObject var style: BubbleStyle
    let renderer: CameraRenderer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CameraSettingsPreview(renderer: renderer)
                .frame(width: 288, height: 162)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text("Size").foregroundStyle(.secondary)
            Picker("Size", selection: $style.size) {
                ForEach(BubbleSize.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            Text("Shape").foregroundStyle(.secondary)
            Picker("Shape", selection: $style.shape) {
                ForEach(BubbleShape.allCases, id: \.self) { shape in
                    Image(systemName: shape.symbol).tag(shape).accessibilityLabel(shape.rawValue)
                }
            }
            .pickerStyle(.segmented).labelsHidden()
            Text("Filter").foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(BubbleFilter.allCases, id: \.self) { filter in
                    Button { style.filter = filter } label: {
                        Text(filter.rawValue).font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 7).padding(.vertical, 6)
                            .background(style.filter == filter ? Color.white.opacity(0.24) : Color.white.opacity(0.07),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(style.filter == filter ? .isSelected : [])
                }
            }
            Button("Background & effects…") { AVCaptureDevice.showSystemUserInterface(.videoEffects) }
            Text("Blur or replace your background with macOS Video Effects")
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
        .font(.system(size: 12)).foregroundStyle(.white)
        .padding(16).frame(width: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
    }
}
