import Foundation

struct Recording: Identifiable, Hashable {
    let id: String
    var url: URL
    var date: Date
    var modified: Date
    var size: Int64

    var title: String { url.deletingPathExtension().lastPathComponent }

    init(url: URL) throws {
        let values = try url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey])
        id = RecordingID.id(for: url)
        self.url = url
        date = values.creationDate ?? Date.distantPast
        modified = values.contentModificationDate ?? date
        size = Int64(values.fileSize ?? 0)
    }
}

// The id lives in the file's extended attributes, so a rename or a move in Finder keeps the link to the
// file's Drive copy.
enum RecordingID {
    private static let key = "io.github.mehedisarkar2k.bubblecast.id"

    static func id(for url: URL) -> String {
        if let existing = read(url) { return existing }
        let new = UUID().uuidString
        let data = Data(new.utf8)
        let result = data.withUnsafeBytes { setxattr(url.path, key, $0.baseAddress, data.count, 0, 0) }
        // A file system without extended attributes still works; its id then follows the path.
        return result == 0 ? new : url.path
    }

    private static func read(_ url: URL) -> String? {
        let size = getxattr(url.path, key, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(url.path, key, $0.baseAddress, size, 0, 0) }
        guard read == size else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
