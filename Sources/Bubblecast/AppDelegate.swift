import AppKit
import AVFoundation
import Carbon
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "io.github.mehedisarkar2k.bubblecast", category: "App")
    let state = BarState()
    let recorder = ScreenRecorder()
    let camera = CameraSession()
    private let style = BubbleStyle()
    var settings: CameraSettingsPanel!
    var bubble: CameraBubble!
    var panel: ControlBar!
    let devices = Devices()
    let countdown = Countdown()
    private var activeCameraID: String?
    var statusMenu: StatusMenu!
    var timer: Timer?
    var startedAt: Date?
    var quitting = false
    private var cameraObserver: NSObjectProtocol?
    private var hotKeys: HotKeys?
    private var cameraOnBeforeClose = false
    private let permissions = PermissionsWindow()

    func applicationDidFinishLaunching(_ notification: Notification) {
        bubble = CameraBubble(renderer: camera.renderer, style: style)
        settings = CameraSettingsPanel(style: style, renderer: camera.renderer)
        panel = ControlBar(state: state, devices: devices, record: { [weak self] in self?.toggleRecording() },
                             camera: { [weak self] in self?.setCamera($0) },
                             settings: { [weak self] in self?.toggleCameraSettings() },
                             fullScreen: { [weak self] in
                                 guard let self else { return }; setFullScreen(!state.fullScreen)
                             },
                             close: { [weak self] in self?.closeBar() })
        devices.onChange = { [weak self] in self?.devicesChanged() }
        devicesChanged()
        countdown.onError = { [weak self] in self?.state.countingDown = false; self?.showError($0) }
        recorder.onStarted = { [weak self] in self?.recordingStarted() }
        recorder.onFinished = { [weak self] url in
            guard let self else { return }
            resetRecording()
            NSWorkspace.shared.activateFileViewerSelecting([url])
            finishQuitting()
        }
        recorder.onError = { [weak self] error in
            guard let self else { return }
            resetRecording()
            showError(error)
            finishQuitting()
        }
        cameraObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: camera.session, queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
            Task { @MainActor [weak self] in
                guard let self else { return }
                settings.close()
                bubble.hide()
                activeCameraID = nil
                camera.stop()
                devices.chooseCamera(nil)
                state.cameraShown = false
                state.fullScreen = false
                showError(error ?? NSError(domain: "Bubblecast", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "The camera session failed."]))
            }
        }
        bubble.onDoubleClick = { [weak self] in
            guard let self else { return }
            setFullScreen(!state.fullScreen)
        }
        registerShortcuts()
        statusMenu = StatusMenu(showBar: { [weak self] in self?.openBar() },
                                showPermissions: { [weak self] in self?.permissions.show() },
                                onError: { [weak self] in self?.showError($0) })
        permissions.onDone = { [weak self] in self?.openBar() }
        permissions.onError = { [weak self] in self?.showError($0) }
        if permissions.allAllowed { panel.show() } else { permissions.show() }
    }

    // Closing the bar closes the recorder: the camera goes off until the bar is opened again.
    private func closeBar() {
        settings.close()
        panel.hide()
        guard !state.recording && !state.busy && !state.countingDown else { return }
        cameraOnBeforeClose = state.cameraShown
        setCamera(nil)
    }

    private func openBar() {
        panel.show()
        if cameraOnBeforeClose && !state.cameraShown {
            cameraOnBeforeClose = false
            setCamera(devices.cameraToRestore)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openBar()
        return false
    }

    private func registerShortcuts() {
        do {
            let keys = try HotKeys()
            try keys.register("record", keyCode: kVK_ANSI_R) { [weak self] in self?.toggleRecording() }
            try keys.register("me", keyCode: kVK_ANSI_M) { [weak self] in
                guard let self else { return }
                setCamera(state.cameraShown ? nil : devices.cameraToRestore)
            }
            try keys.register("full screen", keyCode: kVK_ANSI_F) { [weak self] in
                guard let self else { return }
                setFullScreen(!state.fullScreen)
            }
            hotKeys = keys
        } catch { showError(error) }
    }

    private func devicesChanged() {
        if countdown.screenChanged(to: devices.screen) { state.countingDown = false }
        if let screen = devices.screen {
            settings.close()
            panel.move(to: screen); bubble.move(to: screen)
        }
        let id = devices.cameraID.flatMap { $0.isEmpty ? nil : $0 }
        if id != activeCameraID && !state.cameraBusy { setCamera(id) }
    }

    private func setCamera(_ id: String?) {
        guard !state.cameraBusy else { return }
        guard let id else {
            settings.close()
            bubble.hide(); camera.stop(); activeCameraID = nil
            state.cameraShown = false; state.fullScreen = false
            devices.chooseCamera(nil)
            return
        }
        state.cameraBusy = true
        Task {
            defer { state.cameraBusy = false; devicesChanged() }
            do {
                try await camera.start(deviceID: id)
                activeCameraID = id
                devices.chooseCamera(id)
                bubble.show()
                state.cameraShown = true
            } catch {
                devices.chooseCamera(activeCameraID)
                showError(error)
            }
        }
    }

    private func toggleCameraSettings() {
        guard state.cameraShown, !state.cameraBusy, !state.recording, !state.countingDown, !state.busy else { return }
        settings.toggle(above: panel.window)
    }

    private func setFullScreen(_ enabled: Bool) {
        guard state.cameraShown else { return }
        state.fullScreen = enabled
        bubble.setFullScreen(enabled)
    }

    func showError(_ error: Error) {
        logger.error("\(error.localizedDescription, privacy: .public)")
        let alert = NSAlert()
        alert.messageText = "Bubblecast"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        settings.close()
        countdown.cancel()
        state.countingDown = false
        guard state.recording || state.busy else { return .terminateNow }
        quitting = true
        if state.recording && !state.busy { toggleRecording() }
        return .terminateLater
    }
    func finishQuitting() {
        if quitting { NSApplication.shared.reply(toApplicationShouldTerminate: true) }
    }
}
