import Foundation

// The few Google Drive v3 calls Bubblecast needs. With the drive.file scope it only ever sees files and
// the "Bubblecast" folder that it created itself.
@MainActor
final class DriveClient {
    private let auth: GoogleAuth
    private var folderID: String?
    private static let api = "https://www.googleapis.com/drive/v3/files"
    private static let uploadAPI = "https://www.googleapis.com/upload/drive/v3/files"

    init(auth: GoogleAuth) { self.auth = auth }

    // Creates the file, or replaces the content of `existingID` so its share link keeps working.
    func upload(_ file: URL, name: String, existingID: String?, progress: @escaping @Sendable (Double) -> Void) async throws -> String {
        var start: URLRequest
        var metadata: [String: Any] = ["name": name]
        if let existingID {
            start = URLRequest(url: URL(string: "\(Self.uploadAPI)/\(existingID)?uploadType=resumable&fields=id")!)
            start.httpMethod = "PATCH"
        } else {
            start = URLRequest(url: URL(string: "\(Self.uploadAPI)?uploadType=resumable&fields=id")!)
            start.httpMethod = "POST"
            metadata["parents"] = [try await folder()]
        }
        start.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        start.setValue("video/mp4", forHTTPHeaderField: "X-Upload-Content-Type")
        start.httpBody = try JSONSerialization.data(withJSONObject: metadata)
        let (_, session) = try await send(start)
        guard let location = session.value(forHTTPHeaderField: "Location"), let sessionURL = URL(string: location) else {
            throw AppError.message("Google Drive did not start the upload.")
        }
        // The upload session URL carries its own authorisation.
        var put = URLRequest(url: sessionURL)
        put.httpMethod = "PUT"
        put.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.upload(for: put, fromFile: file, delegate: UploadProgress(progress))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Self.failure(status, data) }
        return try JSONDecoder().decode(DriveFile.self, from: data).id
    }

    func share(_ id: String) async throws -> (permissionID: String, link: String) {
        var request = URLRequest(url: URL(string: "\(Self.api)/\(id)/permissions?fields=id")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["role": "reader", "type": "anyone"])
        let (data, _) = try await send(request)
        let permission = try JSONDecoder().decode(DriveFile.self, from: data).id
        guard let link = try await file(id)?.webViewLink else { throw AppError.message("Google Drive did not return a link.") }
        return (permission, link)
    }

    func unshare(_ id: String, permissionID: String) async throws {
        var request = URLRequest(url: URL(string: "\(Self.api)/\(id)/permissions/\(permissionID)")!)
        request.httpMethod = "DELETE"
        try await sendAllowingMissing(request)
    }

    func rename(_ id: String, to name: String) async throws {
        var request = URLRequest(url: URL(string: "\(Self.api)/\(id)")!)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])
        _ = try await send(request)
    }

    func delete(_ id: String) async throws {
        var request = URLRequest(url: URL(string: "\(Self.api)/\(id)")!)
        request.httpMethod = "DELETE"
        try await sendAllowingMissing(request)
    }

    // nil when the file is gone (deleted or trashed) on Drive.
    func file(_ id: String) async throws -> DriveFile? {
        let request = URLRequest(url: URL(string: "\(Self.api)/\(id)?fields=id,trashed,webViewLink")!)
        do {
            let (data, _) = try await send(request)
            let file = try JSONDecoder().decode(DriveFile.self, from: data)
            return file.trashed == true ? nil : file
        } catch DriveError.notFound {
            return nil
        }
    }

    private func folder() async throws -> String {
        if let folderID { return folderID }
        var search = URLComponents(string: Self.api)!
        search.queryItems = [
            URLQueryItem(name: "q", value: "name = 'Bubblecast' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"),
            URLQueryItem(name: "fields", value: "files(id)"),
        ]
        let (found, _) = try await send(URLRequest(url: search.url!))
        if let existing = try JSONDecoder().decode(FileList.self, from: found).files.first {
            folderID = existing.id
            return existing.id
        }
        var create = URLRequest(url: URL(string: "\(Self.api)?fields=id")!)
        create.httpMethod = "POST"
        create.setValue("application/json", forHTTPHeaderField: "Content-Type")
        create.httpBody = try JSONSerialization.data(withJSONObject: ["name": "Bubblecast", "mimeType": "application/vnd.google-apps.folder"])
        let (data, _) = try await send(create)
        let id = try JSONDecoder().decode(DriveFile.self, from: data).id
        folderID = id
        return id
    }

    private func sendAllowingMissing(_ request: URLRequest) async throws {
        do { _ = try await send(request) } catch DriveError.notFound { return }
    }

    private func send(_ request: URLRequest, retried: Bool = false) async throws -> (Data, HTTPURLResponse) {
        var signed = request
        signed.setValue("Bearer \(try await auth.token())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: signed)
        guard let http = response as? HTTPURLResponse else { throw AppError.message("Google Drive sent no response.") }
        if http.statusCode == 401 && !retried {
            auth.invalidateToken()
            return try await send(request, retried: true)
        }
        if http.statusCode == 404 { throw DriveError.notFound }
        guard (200..<300).contains(http.statusCode) else { throw Self.failure(http.statusCode, data) }
        return (data, http)
    }

    private static func failure(_ status: Int, _ data: Data) -> Error {
        let message = (try? JSONDecoder().decode(DriveErrorBody.self, from: data))?.error.message ?? "HTTP \(status)"
        return AppError.message("Google Drive: \(message)")
    }
}

struct DriveFile: Decodable {
    let id: String
    let trashed: Bool?
    let webViewLink: String?
}

private struct FileList: Decodable { let files: [DriveFile] }
private struct DriveErrorBody: Decodable {
    struct Detail: Decodable { let message: String }
    let error: Detail
}
private enum DriveError: Error { case notFound }

private final class UploadProgress: NSObject, URLSessionTaskDelegate, Sendable {
    private let report: @Sendable (Double) -> Void
    init(_ report: @escaping @Sendable (Double) -> Void) { self.report = report }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        report(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}
