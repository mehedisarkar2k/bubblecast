import Foundation

enum RecordingPaths {
    static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies/Bubblecast", isDirectory: true)
    }

    static func nextFile() throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let now = Date()
        let directory = root.appendingPathComponent(formatter.string(from: now), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
