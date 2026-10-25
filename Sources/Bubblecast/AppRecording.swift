import AppKit

@MainActor
extension AppDelegate {
    func toggleRecording() {
        if countdown.isRunning {
            countdown.cancel()
            state.countingDown = false
            return
        }
        guard !state.busy else { return }
        if state.recording {
            state.busy = true
            Task { await recorder.stop() }
        } else if let screen = devices.screen {
            settings.close()
            state.countingDown = true
            countdown.start(on: screen) { [weak self] in self?.startRecording() }
        }
    }

    func startRecording() {
        settings.close()
        state.countingDown = false
        state.busy = true
        let displayID = devices.screen?.displayID ?? CGMainDisplayID()
        let microphoneID = devices.microphoneID.flatMap { $0.isEmpty ? nil : $0 }
        Task {
            do {
                try await recorder.start(displayID: displayID, microphoneID: microphoneID,
                                         excluding: CGWindowID(panel.window.windowNumber))
            } catch { resetRecording(); showError(error); finishQuitting() }
        }
    }

    func recordingStarted() {
        state.recording = true
        statusMenu.update(recording: state.recording)
        state.busy = false
        startedAt = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let startedAt else { return }
                state.elapsed = Int(Date().timeIntervalSince(startedAt))
            }
        }
        if quitting { toggleRecording() }
    }

    func resetRecording() {
        timer?.invalidate()
        timer = nil
        startedAt = nil
        state.recording = false
        statusMenu.update(recording: state.recording)
        state.busy = false
        state.elapsed = 0
    }

}
