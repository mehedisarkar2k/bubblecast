import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

// Google sign-in for a desktop app: browser consent with PKCE and a 127.0.0.1 redirect, asking only for
// drive.file (files this app creates). The refresh token is kept in the Keychain.
@MainActor
final class GoogleAuth: ObservableObject {
    @Published private(set) var isConnected = false
    private var clientID: String?
    private var clientSecret: String?
    private var accessToken: String?
    private var expiry = Date.distantPast
    private static let refreshAccount = "google.refreshToken"
    private static let clientAccount = "google.client"
    private static let scope = "https://www.googleapis.com/auth/drive.file"

    // The OAuth client comes from a file the user imports once (kept in the Keychain) or from a private
    // build (Config/google-client.json); it is never part of the public source or release.
    var isConfigured: Bool { clientID != nil }

    init() {
        if let stored = try? Keychain.get(Self.clientAccount), let client = Self.parseClient(Data(stored.utf8)) {
            (clientID, clientSecret) = client
        } else if let bundled = Bundle.main.url(forResource: "GoogleClient", withExtension: "plist")
                    .flatMap({ NSDictionary(contentsOf: $0) as? [String: String] }) {
            clientID = bundled["ClientID"]
            clientSecret = bundled["ClientSecret"]
        }
        isConnected = (try? Keychain.get(Self.refreshAccount)) != nil
    }

    func connect() async throws {
        if clientID == nil { try importClient() }
        guard let clientID else { return }
        let verifier = Self.randomString()
        let state = Self.randomString()
        let server = try LoopbackServer()
        defer { server.stop() }
        let redirect = "http://127.0.0.1:\(try await server.start())"
        var authorize = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        authorize.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = authorize.url, NSWorkspace.shared.open(url) else {
            throw AppError.message("The browser could not be opened for Google sign-in.")
        }
        let reply = try await server.waitForCallback()
        NSApp.activate()
        guard reply["state"] == state else { throw AppError.message("Google sign-in failed a security check. Please try again.") }
        if let error = reply["error"] { throw AppError.message("Google sign-in was not completed (\(error)).") }
        guard let code = reply["code"] else { throw AppError.message("Google did not return a sign-in code.") }
        let tokens = try await tokenRequest([
            "grant_type": "authorization_code", "code": code,
            "redirect_uri": redirect, "code_verifier": verifier,
        ])
        guard let refresh = tokens.refresh_token else {
            throw AppError.message("Google did not return a lasting sign-in. Please try Connect again.")
        }
        try Keychain.set(refresh, for: Self.refreshAccount)
        remember(tokens)
        isConnected = true
    }

    // Asks for the "Desktop app" JSON downloaded from Google Cloud and keeps it in the Keychain.
    private func importClient() throws {
        let panel = NSOpenPanel()
        panel.title = "Choose your Google client file"
        panel.message = "Pick the OAuth \"Desktop app\" JSON you downloaded from Google Cloud. Bubblecast keeps it in your Keychain; you can delete the file afterwards."
        panel.allowedContentTypes = [.json]
        panel.prompt = "Use This File"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = try Data(contentsOf: url)
        guard let client = Self.parseClient(data) else {
            throw AppError.message("This is not a Google \"Desktop app\" client file. In Google Cloud choose Clients → Create client → Desktop app → Download JSON.")
        }
        try Keychain.set(String(decoding: data, as: UTF8.self), for: Self.clientAccount)
        (clientID, clientSecret) = client
    }

    private static func parseClient(_ data: Data) -> (String, String?)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let installed = json["installed"] as? [String: Any],
              let id = installed["client_id"] as? String else { return nil }
        return (id, installed["client_secret"] as? String)
    }

    func disconnect() throws {
        if let token = try Keychain.get(Self.refreshAccount) {
            // Revoking is a courtesy; the local sign-in is removed even when Google cannot be reached.
            var revoke = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
            revoke.httpMethod = "POST"
            revoke.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            revoke.httpBody = Self.form(["token": token])
            URLSession.shared.dataTask(with: revoke).resume()
        }
        try Keychain.delete(Self.refreshAccount)
        accessToken = nil
        isConnected = false
    }

    func token() async throws -> String {
        if let accessToken, expiry > Date().addingTimeInterval(60) { return accessToken }
        guard let refresh = try Keychain.get(Self.refreshAccount) else {
            isConnected = false
            throw AppError.message("Google Drive is not connected.")
        }
        do {
            let tokens = try await tokenRequest(["grant_type": "refresh_token", "refresh_token": refresh])
            remember(tokens)
            return tokens.access_token
        } catch AuthError.revoked {
            try Keychain.delete(Self.refreshAccount)
            isConnected = false
            throw AppError.message("Google Drive access has ended. Please connect Google Drive again.")
        }
    }

    func invalidateToken() { accessToken = nil }

    private func remember(_ tokens: TokenResponse) {
        accessToken = tokens.access_token
        expiry = Date().addingTimeInterval(TimeInterval(tokens.expires_in))
    }

    private func tokenRequest(_ fields: [String: String]) async throws -> TokenResponse {
        guard let clientID else { throw AppError.message("Google Drive is not set up in this build.") }
        var fields = fields
        fields["client_id"] = clientID
        if let clientSecret { fields["client_secret"] = clientSecret }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(fields)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let reason = (try? JSONDecoder().decode(TokenError.self, from: data))?.error ?? "HTTP \(status)"
            if reason == "invalid_grant" { throw AuthError.revoked }
            throw AppError.message("Google sign-in failed (\(reason)).")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private static func form(_ fields: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        // URLComponents leaves "+" alone, but form encoding reads it as a space.
        return Data((components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
    }

    private static func randomString() -> String {
        base64URL(Data((0..<32).map { _ in UInt8.random(in: 0...255) }))
    }

    private static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

private enum AuthError: Error { case revoked }

private struct TokenResponse: Decodable {
    let access_token: String
    let expires_in: Int
    let refresh_token: String?
}

private struct TokenError: Decodable { let error: String }
