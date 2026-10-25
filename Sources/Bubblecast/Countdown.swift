import AppKit
import SwiftUI

@MainActor
final class Countdown {
    private var task: Task<Void, Never>?
    private var window: NSPanel?
    private var screenID: String?
    var onError: ((Error) -> Void)?
    var isRunning: Bool { task != nil }

    func start(on screen: NSScreen, completion: @escaping () -> Void) {
        cancel()
        let frame = NSRect(x: screen.frame.midX - 60, y: screen.frame.midY - 60, width: 120, height: 120)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window = panel
        screenID = screen.persistentID
        task = Task { [weak self] in
            for number in (1...3).reversed() {
                panel.contentView = NSHostingView(rootView: Text("\(number)")
                    .font(.system(size: 72, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white).frame(width: 120, height: 120)
                    .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 28)))
                panel.orderFrontRegardless()
                do { try await Task.sleep(for: .seconds(1)) }
                catch is CancellationError { return }
                catch { self?.cancel(); self?.onError?(error); return }
            }
            self?.cancel()
            completion()
        }
    }

    func screenChanged(to screen: NSScreen?) -> Bool {
        guard isRunning, screen?.persistentID != screenID else { return false }
        cancel()
        return true
    }

    func cancel() {
        task?.cancel()
        task = nil
        window?.orderOut(nil)
        window = nil
    }
}
