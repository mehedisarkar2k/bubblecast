import AppKit
import AVFoundation

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    var persistentID: String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return String(displayID)
        }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

@MainActor
final class Devices: ObservableObject {
    @Published private(set) var cameras: [AVCaptureDevice] = []
    @Published private(set) var microphones: [AVCaptureDevice] = []
    @Published private(set) var screens: [NSScreen] = []
    @Published var cameraID: String?
    @Published var microphoneID: String?
    @Published var screenID: String?
    private(set) var lastCameraID: String?
    var onChange: (() -> Void)?
    private var observers: [NSObjectProtocol] = []
    private let defaults = UserDefaults.standard

    var screen: NSScreen? { screens.first { $0.persistentID == screenID } ?? screens.first }
    var cameraName: String { cameras.first { $0.uniqueID == cameraID }?.localizedName ?? "No camera" }
    var microphoneName: String { microphones.first { $0.uniqueID == microphoneID }?.localizedName ?? "No microphone" }

    init() {
        cameraID = defaults.string(forKey: "cameraID")
        microphoneID = defaults.string(forKey: "microphoneID")
        screenID = defaults.string(forKey: "screenID")
        lastCameraID = defaults.string(forKey: "lastCameraID")
        refresh()
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification,
                     NSApplication.didChangeScreenParametersNotification, NSMenu.didBeginTrackingNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in Task { @MainActor [weak self] in self?.refresh() }
            })
        }
    }

    func refresh() {
        cameras = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                                   mediaType: .video, position: .unspecified).devices
        microphones = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external],
                                                       mediaType: .audio, position: .unspecified).devices
        screens = NSScreen.screens
        if let cameraID, !cameraID.isEmpty, !cameras.contains(where: { $0.uniqueID == cameraID }) {
            self.cameraID = AVCaptureDevice.default(for: .video)?.uniqueID ?? cameras.first?.uniqueID
        }
        if microphoneID == nil || (microphoneID != "" && !microphones.contains { $0.uniqueID == microphoneID }) {
            microphoneID = AVCaptureDevice.default(for: .audio)?.uniqueID ?? microphones.first?.uniqueID
        }
        if !screens.contains(where: { $0.persistentID == screenID }) {
            screenID = screens.first { $0.displayID == CGMainDisplayID() }?.persistentID ?? screens.first?.persistentID
        }
        onChange?()
    }

    func chooseCamera(_ id: String?) {
        cameraID = id ?? ""
        defaults.set(id ?? "", forKey: "cameraID")
        if let id {
            lastCameraID = id
            defaults.set(id, forKey: "lastCameraID")
        }
    }

    func chooseMicrophone(_ id: String?) {
        microphoneID = id ?? ""
        defaults.set(id ?? "", forKey: "microphoneID")
    }

    func chooseScreen(_ id: String) {
        screenID = id
        defaults.set(id, forKey: "screenID")
        onChange?()
    }

    var cameraToRestore: String? {
        cameras.first { $0.uniqueID == lastCameraID }?.uniqueID
            ?? AVCaptureDevice.default(for: .video)?.uniqueID ?? cameras.first?.uniqueID
    }
}
