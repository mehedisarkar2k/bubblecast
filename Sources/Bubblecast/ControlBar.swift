import AppKit
import AVFoundation
import Combine
import SwiftUI

@MainActor
final class BarState: ObservableObject {
    @Published var recording = false
    @Published var countingDown = false
    @Published var busy = false
    @Published var cameraBusy = false
    @Published var cameraShown = false
    @Published var fullScreen = false
    @Published var elapsed = 0
    var time: String { String(format: "%02d:%02d", elapsed / 60, elapsed % 60) }
}

@MainActor
final class ControlBar {
    let window: NSPanel
    private var screenID: String?
    private var subscription: AnyCancellable?

    init(state: BarState, devices: Devices, record: @escaping () -> Void,
         camera: @escaping (String?) -> Void, settings: @escaping () -> Void, fullScreen: @escaping () -> Void, library: @escaping () -> Void,
         close: @escaping () -> Void) {
        window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 716, height: 44),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: BarView(
            state: state, devices: devices, record: record, camera: camera, settings: settings, fullScreen: fullScreen,
            library: library, close: close))
        subscription = state.$recording.sink { [weak self] recording in
            guard let self else { return }
            let width: CGFloat = recording ? 260 : 746
            let centre = window.frame.midX
            window.setFrame(NSRect(x: centre - width / 2, y: window.frame.minY, width: width, height: 44), display: true)
        }
    }

    func move(to screen: NSScreen) {
        guard screenID != screen.persistentID else { return }
        screenID = screen.persistentID
        window.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - window.frame.width / 2,
                                      y: screen.visibleFrame.minY + 24))
    }

    func show() { window.orderFrontRegardless() }
    func hide() { window.orderOut(nil) }
}

@MainActor
private struct BarView: View {
    @ObservedObject var state: BarState
    @ObservedObject var devices: Devices
    let record: () -> Void
    let camera: (String?) -> Void
    let settings: () -> Void
    let fullScreen: () -> Void
    let library: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if state.recording {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    Circle().fill(.red)
                        .opacity(0.45 + 0.55 * abs(sin(context.date.timeIntervalSinceReferenceDate * .pi)))
                        .frame(width: 8, height: 8)
                }
                Text(state.time).monospacedDigit().frame(width: 52)
                Button(action: record) { Image(systemName: "stop.fill").foregroundStyle(.red) }
                    .help("Stop recording").disabled(state.busy)
                Button(action: fullScreen) {
                    Image(systemName: state.fullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .help("Full screen me").disabled(!state.cameraShown || state.cameraBusy)
                closeButton
            } else {
                Menu {
                    ForEach(devices.screens, id: \.persistentID) { screen in
                        Button { devices.chooseScreen(screen.persistentID) } label: {
                            menuItem(screen.localizedName, selected: devices.screenID == screen.persistentID)
                        }
                    }
                } label: { label(devices.screen?.localizedName ?? "Screen", icon: "display") }
                .disabled(state.countingDown || state.busy)
                Menu {
                    Button { camera(nil) } label: { menuItem("No camera", selected: !state.cameraShown) }
                    ForEach(devices.cameras, id: \.uniqueID) { device in
                        Button { camera(device.uniqueID) } label: {
                            menuItem(device.localizedName, selected: state.cameraShown && devices.cameraID == device.uniqueID)
                        }
                    }
                } label: { label(state.cameraShown ? devices.cameraName : "No camera", icon: state.cameraShown ? "video" : "video.slash") }
                .disabled(state.cameraBusy || state.countingDown || state.busy)
                Button(action: settings) { Image(systemName: "slider.horizontal.3").frame(width: 20, height: 28) }
                    .help("Camera settings")
                    .disabled(!state.cameraShown || state.cameraBusy || state.countingDown || state.busy)
                Menu {
                    Button { devices.chooseMicrophone(nil) } label: {
                        menuItem("No microphone", selected: devices.microphoneID?.isEmpty != false)
                    }
                    ForEach(devices.microphones, id: \.uniqueID) { device in
                        Button { devices.chooseMicrophone(device.uniqueID) } label: {
                            menuItem(device.localizedName, selected: devices.microphoneID == device.uniqueID)
                        }
                    }
                } label: { label(devices.microphoneName, icon: devices.microphoneID?.isEmpty == false ? "mic" : "mic.slash") }
                .disabled(state.countingDown || state.busy)
                Button(state.countingDown ? "Cancel countdown" : "Start recording", action: record)
                    .fontWeight(.semibold).padding(.horizontal, 12).frame(height: 30)
                    .background(.red, in: Capsule())
                    .disabled(state.busy)
                Button(action: library) { Image(systemName: "film.stack") }
                    .help("Library: watch, rename, upload and share recordings")
                closeButton
            }
        }
        .menuStyle(.borderlessButton).buttonStyle(.plain)
        .font(.system(size: 12)).foregroundStyle(.white)
        .padding(.horizontal, 16).frame(width: state.recording ? 260 : 746, height: 44)
        .background { Capsule().fill(.ultraThinMaterial).gesture(WindowDragGesture()) }
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
    }

    private var closeButton: some View {
        Button(action: close) { Image(systemName: "xmark").foregroundStyle(.secondary) }
            .help("Hide bar (menu bar icon → Show bar)")
    }

    private func label(_ title: String, icon: String) -> some View {
        Label { Text(title).lineLimit(1).truncationMode(.tail) } icon: { Image(systemName: icon) }
            .frame(width: 140, alignment: .leading)
    }

    @ViewBuilder
    private func menuItem(_ title: String, selected: Bool) -> some View {
        if selected { Label(title, systemImage: "checkmark") } else { Text(title) }
    }
}
