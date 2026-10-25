import AppKit
import AVFoundation

// All recordings on disk plus their Drive state. The local file is always the main copy.
@MainActor
final class RecordingLibrary: ObservableObject {
    @Published private(set) var recordings: [Recording] = []
    @Published private(set) var thumbnails: [String: NSImage] = [:]
    @Published private(set) var durations: [String: Double] = [:]
    @Published private(set) var uploads: [String: Double] = [:]
    @Published private(set) var waiting: Set<String> = []
    @Published var autoUpload = UserDefaults.standard.bool(forKey: "cloud.autoUpload") {
        didSet { UserDefaults.standard.set(autoUpload, forKey: "cloud.autoUpload") }
    }
    @Published var lastError: String?
    let auth = GoogleAuth()
    private lazy var drive = DriveClient(auth: auth)
    private let cloud = CloudStore()
    private var retryTimer: Timer?

    init() {
        // Uploads that failed (offline, Drive down) are tried again every minute.
        retryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.retryWaiting() }
        }
    }

    func refresh() {
        let folders = Set([RecordingPaths.root.standardizedFileURL, RecordingPaths.defaultRoot.standardizedFileURL])
        var found: [Recording] = []
        for folder in folders {
            guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil,
                                                             options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in files where url.pathExtension.lowercased() == "mp4" {
                do { found.append(try Recording(url: url)) } catch { report(error) }
            }
        }
        recordings = found.sorted { $0.date > $1.date }
        for recording in recordings where thumbnails[recording.id] == nil { Task { await loadPreview(recording) } }
    }

    func status(of recording: Recording) -> CloudStatus {
        if let progress = uploads[recording.id] { return .uploading(progress) }
        if waiting.contains(recording.id) { return .waiting }
        guard let record = cloud[recording.id] else { return .local }
        if record.missing { return .missing }
        if abs(record.uploadedModified.timeIntervalSince(recording.modified)) > 1 { return .outdated }
        return record.link != nil ? .shared : .onDrive
    }

    func link(of recording: Recording) -> String? { cloud[recording.id]?.link }

    var storageSummary: String {
        let local = recordings.reduce(Int64(0)) { $0 + $1.size }
        let onDrive = recordings.filter { cloud[$0.id].map { !$0.missing } ?? false }.reduce(Int64(0)) { $0 + $1.size }
        let format = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        return "\(recordings.count) recordings · \(format(local)) on this Mac · \(format(onDrive)) on Drive"
    }

    func recordingFinished(_ url: URL) {
        refresh()
        guard autoUpload, auth.isConnected, let recording = recordings.first(where: { $0.url == url }) else { return }
        upload(recording)
    }

    // MARK: Local actions

    func play(_ recording: Recording) { NSWorkspace.shared.open(recording.url) }
    func showInFinder(_ recording: Recording) { NSWorkspace.shared.activateFileViewerSelecting([recording.url]) }

    func rename(_ recording: Recording, to name: String) {
        let clean = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != recording.title else { return }
        let target = recording.url.deletingLastPathComponent().appendingPathComponent(clean + ".mp4")
        do {
            guard !FileManager.default.fileExists(atPath: target.path) else {
                throw AppError.message("A recording named \"\(clean)\" already exists.")
            }
            try FileManager.default.moveItem(at: recording.url, to: target)
        } catch { return report(error) }
        refresh()
        guard let record = cloud[recording.id], !record.missing else { return }
        Task { do { try await drive.rename(record.fileID, to: clean + ".mp4") } catch { report(error) } }
    }

    func moveToTrash(_ recordings: [Recording]) {
        NSWorkspace.shared.recycle(recordings.map(\.url)) { [weak self] _, error in
            Task { @MainActor [weak self] in
                if let error { self?.report(error) }
                self?.refresh()
            }
        }
    }

    func deleteEverywhere(_ recordings: [Recording]) {
        for recording in recordings where cloud[recording.id] != nil { removeFromDrive(recording) }
        moveToTrash(recordings)
    }

    // MARK: Drive actions

    func connectDrive() {
        Task {
            do { try await auth.connect() } catch { report(error) }
        }
    }

    func disconnectDrive() {
        do { try auth.disconnect() } catch { report(error) }
    }

    func upload(_ recording: Recording, thenShare: Bool = false) {
        guard uploads[recording.id] == nil else { return }
        waiting.remove(recording.id)
        uploads[recording.id] = 0
        let existing = cloud[recording.id].flatMap { $0.missing ? nil : $0.fileID }
        let id = recording.id
        Task {
            defer { uploads[id] = nil }
            do {
                let fileID = try await drive.upload(recording.url, name: recording.url.lastPathComponent, existingID: existing) { progress in
                    Task { @MainActor in
                        if self.uploads[id] != nil { self.uploads[id] = progress }
                    }
                }
                var record = cloud[id] ?? CloudRecord(fileID: fileID, uploadedModified: recording.modified)
                record.fileID = fileID
                record.uploadedModified = recording.modified
                record.missing = false
                cloud[id] = record
                objectWillChange.send()
                if thenShare { await share(recording) }
            } catch let error as URLError {
                waiting.insert(id)
                report(AppError.message("Upload paused, Bubblecast will try again: \(error.localizedDescription)"))
            } catch {
                report(error)
            }
        }
    }

    func copyLink(_ recording: Recording) {
        if let link = cloud[recording.id]?.link {
            copy(link)
        } else if cloud[recording.id] == nil || cloud[recording.id]?.missing == true {
            upload(recording, thenShare: true)
        } else {
            Task { await share(recording) }
        }
    }

    func stopSharing(_ recording: Recording) {
        guard var record = cloud[recording.id], let permission = record.permissionID else { return }
        Task {
            do {
                try await drive.unshare(record.fileID, permissionID: permission)
                record.permissionID = nil
                record.link = nil
                cloud[recording.id] = record
                objectWillChange.send()
            } catch { report(error) }
        }
    }

    func removeFromDrive(_ recording: Recording) {
        guard let record = cloud[recording.id] else { return }
        Task {
            do {
                try await drive.delete(record.fileID)
                cloud[recording.id] = nil
                objectWillChange.send()
            } catch { report(error) }
        }
    }

    // Marks Drive copies that were deleted or trashed in Drive itself.
    func checkDrive() {
        guard auth.isConnected else { return }
        Task {
            for recording in recordings {
                guard var record = cloud[recording.id] else { continue }
                do {
                    let missing = try await drive.file(record.fileID) == nil
                    guard missing != record.missing else { continue }
                    record.missing = missing
                    cloud[recording.id] = record
                    objectWillChange.send()
                } catch { return report(error) }
            }
        }
    }

    private func share(_ recording: Recording) async {
        guard var record = cloud[recording.id] else { return }
        do {
            let shared = try await drive.share(record.fileID)
            record.permissionID = shared.permissionID
            record.link = shared.link
            cloud[recording.id] = record
            objectWillChange.send()
            copy(shared.link)
        } catch { report(error) }
    }

    private func retryWaiting() {
        guard auth.isConnected else { return }
        for recording in recordings where waiting.contains(recording.id) { upload(recording) }
    }

    private func copy(_ link: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
    }

    private func loadPreview(_ recording: Recording) async {
        let asset = AVURLAsset(url: recording.url)
        do {
            durations[recording.id] = try await asset.load(.duration).seconds
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 480, height: 300)
            let (image, _) = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600))
            thumbnails[recording.id] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        } catch {
            // A recording that is still being written or is damaged simply shows no preview.
            thumbnails[recording.id] = NSImage(systemSymbolName: "film", accessibilityDescription: nil)
        }
    }

    private func report(_ error: Error) {
        lastError = error.localizedDescription
    }
}
