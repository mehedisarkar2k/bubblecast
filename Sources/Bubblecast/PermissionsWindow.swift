import AppKit
import AVFoundation
import SwiftUI

enum PermissionState { case allowed, notAsked, denied }

@MainActor
final class PermissionsModel: ObservableObject {
    @Published var camera = PermissionState.notAsked
    @Published var microphone = PermissionState.notAsked
    @Published var screenAllowed = false
    @Published var screenRequested = false
    var onError: ((Error) -> Void)?

    var allAllowed: Bool { camera == .allowed && microphone == .allowed && screenAllowed }

    func refresh() {
        camera = Self.state(for: .video)
        microphone = Self.state(for: .audio)
        screenAllowed = CGPreflightScreenCaptureAccess()
    }

    func request(_ type: AVMediaType) {
        guard Self.state(for: type) == .notAsked else {
            openSettings(type == .video ? "Privacy_Camera" : "Privacy_Microphone")
            return
        }
        Task {
            _ = await AVCaptureDevice.requestAccess(for: type)
            refresh()
        }
    }

    // Access is missing, so any saved entry is useless (often one left by an older copy of the app that
    // still shows as on in System Settings); clearing it first means one toggle always works.
    func requestScreen() {
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "ScreenCapture", Bundle.main.bundleIdentifier ?? "io.github.mehedisarkar2k.bubblecast"]
        do {
            try reset.run()
            reset.waitUntilExit()
            guard reset.terminationStatus == 0 else {
                throw AppError.message("Resetting the screen recording permission failed (tccutil exit \(reset.terminationStatus)).")
            }
            screenRequested = true
            CGRequestScreenCaptureAccess()
            openSettings("Privacy_ScreenCapture")
        } catch {
            onError?(error)
        }
    }

    private func openSettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func state(for type: AVMediaType) -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized: .allowed
        case .notDetermined: .notAsked
        default: .denied
        }
    }
}

@MainActor
final class PermissionsWindow: NSObject, NSWindowDelegate {
    private let model = PermissionsModel()
    private var window: NSWindow?
    private var timer: Timer?
    var onDone: (() -> Void)?
    var onError: ((Error) -> Void)?

    var allAllowed: Bool {
        model.refresh()
        return model.allAllowed
    }

    func show() {
        model.refresh()
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 340),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Set up Bubblecast"
            model.onError = { [weak self] in self?.onError?($0) }
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: PermissionsView(
                model: model, finish: { [weak self] in self?.window?.close() },
                restart: { [weak self] in self?.restart() }))
            self.window = window
        }
        window?.center()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.model.refresh() }
        }
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        onDone?()
    }

    // macOS applies a new screen recording permission only to a fresh launch of the app.
    private func restart() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        Task {
            do {
                _ = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
                NSApp.terminate(nil)
            } catch {
                onError?(error)
            }
        }
    }
}

private struct PermissionsView: View {
    @ObservedObject var model: PermissionsModel
    let finish: () -> Void
    let restart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Allow these once, and recording will never stop to ask.")
                .foregroundStyle(.secondary)
            row("video.fill", "Camera", "Shows you in the bubble") { control(model.camera) { model.request(.video) } }
            row("mic.fill", "Microphone", "Records your voice") { control(model.microphone) { model.request(.audio) } }
            row("rectangle.dashed.badge.record", "Screen Recording", "Records the screen you choose") { screenControl }
            Spacer()
            HStack {
                Button("Skip for now", action: finish).buttonStyle(.link)
                Spacer()
                Button("Continue", action: finish)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.allAllowed)
            }
        }
        .padding(24)
        .frame(width: 460, height: 340)
    }

    private func row(_ icon: String, _ title: String, _ reason: String,
                     @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title2).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).bold()
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            control()
        }
    }

    @ViewBuilder
    private func control(_ state: PermissionState, allow: @escaping () -> Void) -> some View {
        switch state {
        case .allowed: allowedLabel
        case .notAsked: Button("Allow", action: allow)
        case .denied: Button("Open Settings", action: allow)
        }
    }

    @ViewBuilder
    private var screenControl: some View {
        if model.screenAllowed {
            allowedLabel
        } else if model.screenRequested {
            Button("Restart Bubblecast", action: restart)
        } else {
            Button("Allow") { model.requestScreen() }
        }
    }

    private var allowedLabel: some View {
        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
    }
}
