import Foundation

enum RecordingPaths {
    static let defaultRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Movies/Bubblecast", isDirectory: true)

    static var root: URL {
        guard let path = UserDefaults.standard.string(forKey: "recordingsFolder") else { return defaultRoot }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func setRoot(_ url: URL?) {
        UserDefaults.standard.set(url?.path, forKey: "recordingsFolder")
    }

    // A synced folder can be missing or offline at the end of a recording; keep the video in the
    // default folder rather than lose it.
    static func save(_ file: URL, to destination: URL) throws -> URL {
        do {
            try FileManager.default.moveItem(at: file, to: destination)
            return destination
        } catch {
            let fallback = defaultRoot
                .appendingPathComponent(destination.deletingLastPathComponent().lastPathComponent, isDirectory: true)
                .appendingPathComponent(destination.lastPathComponent)
            try FileManager.default.createDirectory(at: fallback.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: file, to: fallback)
            return fallback
        }
    }

    static func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Bubblecast-\(UUID().uuidString).mp4")
    }

    static func nextFile() throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let now = Date()
        var directory = root.appendingPathComponent(formatter.string(from: now), isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            directory = defaultRoot.appendingPathComponent(formatter.string(from: now), isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        formatter.dateFormat = "HH-mm-ss"
        let file = directory.appendingPathComponent(formatter.string(from: now) + ".mp4")
        guard !FileManager.default.fileExists(atPath: file.path) else {
            throw AppError.message("A recording already exists for this second. Please try again.")
        }
        return file
    }
}

enum AppError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): message
        }
    }
}
