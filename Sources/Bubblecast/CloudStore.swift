import Foundation
import OSLog

struct CloudRecord: Codable {
    var fileID: String
    var uploadedModified: Date
    var permissionID: String?
    var link: String?
    var missing = false
}

enum CloudStatus: Equatable {
    case local, waiting, uploading(Double), onDrive, shared, outdated, missing

    var label: String {
        switch self {
        case .local: "On this Mac"
        case .waiting: "Waiting to upload"
        case .uploading(let progress): "Uploading \(Int(progress * 100))%"
        case .onDrive: "On Drive"
        case .shared: "Shared"
        case .outdated: "Drive copy out of date"
        case .missing: "Missing on Drive"
        }
    }

    var symbol: String {
        switch self {
        case .local: "laptopcomputer"
        case .waiting: "clock"
        case .uploading: "arrow.up.circle"
        case .onDrive: "checkmark.icloud"
        case .shared: "link"
        case .outdated: "exclamationmark.icloud"
        case .missing: "questionmark.circle"
        }
    }
}

// Remembers which local recording has which Drive file, keyed by RecordingID.
@MainActor
final class CloudStore {
    private(set) var records: [String: CloudRecord] = [:]
    private let file: URL
    private let logger = Logger(subsystem: "io.github.mehedisarkar2k.bubblecast", category: "CloudStore")

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        file = support.appendingPathComponent("Bubblecast/cloud.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            records = try JSONDecoder().decode([String: CloudRecord].self, from: Data(contentsOf: file))
        } catch {
            logger.error("Could not read cloud records: \(error.localizedDescription, privacy: .public)")
        }
    }

    subscript(id: String) -> CloudRecord? {
        get { records[id] }
        set {
            records[id] = newValue
            save()
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(records).write(to: file, options: .atomic)
        } catch {
            logger.error("Could not save cloud records: \(error.localizedDescription, privacy: .public)")
        }
    }
}
