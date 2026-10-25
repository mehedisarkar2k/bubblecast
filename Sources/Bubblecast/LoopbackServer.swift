import Foundation
import Network

// A one-shot web server on 127.0.0.1 that receives Google's sign-in redirect, the method Google
// recommends for desktop apps. All state is confined to `queue`.
final class LoopbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "io.github.mehedisarkar2k.bubblecast.oauth")
    private var ready: CheckedContinuation<UInt16, Error>?
    private var callback: CheckedContinuation<[String: String], Error>?
    private var result: Result<[String: String], Error>?

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                ready = continuation
                listener.stateUpdateHandler = { [weak self] state in self?.stateChanged(state) }
                listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
                listener.start(queue: queue)
            }
        }
    }

    func waitForCallback(timeout: TimeInterval = 300) async throws -> [String: String] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                if let result { return continuation.resume(with: result) }
                callback = continuation
                queue.asyncAfter(deadline: .now() + timeout) { [self] in
                    finish(.failure(AppError.message("Google sign-in timed out. Please try again.")))
                }
            }
        }
    }

    func stop() {
        queue.async { [self] in listener.cancel() }
    }

    private func stateChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            ready?.resume(returning: listener.port?.rawValue ?? 0)
            ready = nil
        case .failed(let error):
            ready?.resume(throwing: error)
            ready = nil
            finish(.failure(error))
        default:
            break
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            guard let self else { return }
            let requestLine = data.flatMap { String(data: $0, encoding: .utf8) }?.components(separatedBy: "\r\n").first ?? ""
            let target = requestLine.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let query = URLComponents(string: "http://127.0.0.1\(target)")?.queryItems ?? []
            let isCallback = query.contains { $0.name == "code" || $0.name == "error" }
            let body = isCallback
                ? "<html><body style=\"font-family:-apple-system;text-align:center;padding-top:80px\"><h2>Bubblecast is connected to Google Drive.</h2><p>You can close this tab.</p></body></html>"
                : "Not found"
            let response = "HTTP/1.1 \(isCallback ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            guard isCallback else { return }
            var values: [String: String] = [:]
            for item in query { values[item.name] = item.value ?? "" }
            finish(.success(values))
        }
    }

    private func finish(_ value: Result<[String: String], Error>) {
        guard result == nil else { return }
        result = value
        callback?.resume(with: value)
        callback = nil
        listener.cancel()
    }
}
