import AuthenticationServices
import CryptoKit
import Foundation
import Security

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

nonisolated enum GoogleDriveOAuthError: Error, Equatable, LocalizedError, Sendable {
    case notConfigured
    case cancelled
    case invalidCallback
    case stateMismatch
    case notSignedIn
    case tokenExchangeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            String(localized: "Google Drive is not configured.")
        case .cancelled:
            String(localized: "Google Drive sign-in was cancelled.")
        case .invalidCallback:
            String(localized: "Google Drive sign-in did not finish.")
        case .stateMismatch:
            String(localized: "Google Drive sign-in could not be verified.")
        case .notSignedIn:
            String(localized: "Google Drive is not linked.")
        case .tokenExchangeFailed(let message):
            String(localized: "Google Drive sign-in failed. \(message)")
        }
    }
}

@MainActor
final class GoogleDriveOAuthClient {
    static let shared = GoogleDriveOAuthClient()

    private let tokenStore: GoogleDriveTokenStore
    private let session: URLSession
    private var activeAuthSession: ASWebAuthenticationSession?
    private var presentationContext: GoogleDriveAuthPresentationContext?

    init(
        tokenStore: GoogleDriveTokenStore = .shared,
        session: URLSession = .shared
    ) {
        self.tokenStore = tokenStore
        self.session = session
    }

    func signIn(from window: Any? = nil) async throws -> GoogleDriveCredentials {
        guard GoogleDriveOAuthConfig.isConfigured else {
            throw GoogleDriveOAuthError.notConfigured
        }

        let verifier = try Self.randomBase64URL(byteCount: 32)
        let challenge = Self.codeChallenge(for: verifier)
        let state = try Self.randomBase64URL(byteCount: 32)
        let authURL = try Self.authorizationURL(challenge: challenge, state: state)
        let context = GoogleDriveAuthPresentationContext(window: window)

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let box = GoogleDriveAuthContinuationBox(continuation)
            let authSession = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: GoogleDriveOAuthConfig.callbackURLScheme
            ) { callbackURL, error in
                box.resume(callbackURL: callbackURL, error: error)
            }
            authSession.presentationContextProvider = context
            authSession.prefersEphemeralWebBrowserSession = false
            self.presentationContext = context
            self.activeAuthSession = authSession
            guard authSession.start() else {
                self.activeAuthSession = nil
                self.presentationContext = nil
                box.resume(
                    callbackURL: nil,
                    error: GoogleDriveOAuthError.tokenExchangeFailed(
                        String(localized: "Google Drive sign-in could not start.")
                    )
                )
                return
            }
        }
        activeAuthSession = nil
        presentationContext = nil

        let code = try Self.authorizationCode(from: callbackURL, expectedState: state)
        let credentials = try await exchangeAuthorizationCode(code, verifier: verifier)
        try tokenStore.save(credentials)
        return credentials
    }

    func refreshIfNeeded() async throws -> GoogleDriveCredentials {
        guard let stored = tokenStore.load() else {
            throw GoogleDriveOAuthError.notSignedIn
        }
        let refreshDeadline = stored.expiresAt.addingTimeInterval(-60)
        if refreshDeadline > Date.now {
            return stored
        }
        guard stored.refreshToken.isEmpty == false else {
            throw GoogleDriveOAuthError.notSignedIn
        }
        let refreshed = try await refreshAccessToken(stored)
        try tokenStore.save(refreshed)
        return refreshed
    }

    func signOut() {
        tokenStore.delete()
    }

    private func exchangeAuthorizationCode(_ code: String, verifier: String) async throws -> GoogleDriveCredentials {
        guard let url = URL(string: "https://www.googleapis.com/oauth2/v4/token") else {
            throw GoogleDriveOAuthError.tokenExchangeFailed(String(localized: "Google Drive sign-in failed."))
        }
        return try await requestToken(
            url: url,
            body: [
                "code": code,
                "client_id": GoogleDriveOAuthConfig.clientID,
                "redirect_uri": GoogleDriveOAuthConfig.redirectURI,
                "grant_type": "authorization_code",
                "code_verifier": verifier
            ],
            existing: nil
        )
    }

    private func refreshAccessToken(_ existing: GoogleDriveCredentials) async throws -> GoogleDriveCredentials {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            throw GoogleDriveOAuthError.tokenExchangeFailed(String(localized: "Google Drive sign-in failed."))
        }
        return try await requestToken(
            url: url,
            body: [
                "refresh_token": existing.refreshToken,
                "client_id": GoogleDriveOAuthConfig.clientID,
                "grant_type": "refresh_token"
            ],
            existing: existing
        )
    }

    private func requestToken(
        url: URL,
        body: [String: String],
        existing: GoogleDriveCredentials?
    ) async throws -> GoogleDriveCredentials {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GoogleDriveOAuthError.tokenExchangeFailed(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let payload = (try? JSONDecoder().decode(GoogleDriveTokenResponse.self, from: data)) ?? GoogleDriveTokenResponse()
        if (200..<300).contains(status) == false || payload.accessToken == nil {
            let message = payload.userFacingMessage ?? Self.fallbackMessage(from: data, status: status)
            throw GoogleDriveOAuthError.tokenExchangeFailed(message)
        }

        guard let accessToken = payload.accessToken, accessToken.isEmpty == false else {
            throw GoogleDriveOAuthError.tokenExchangeFailed(String(localized: "Google Drive did not return a token."))
        }
        let refreshToken = payload.refreshToken?.isEmpty == false
            ? (payload.refreshToken ?? "")
            : (existing?.refreshToken ?? "")
        guard refreshToken.isEmpty == false else {
            throw GoogleDriveOAuthError.tokenExchangeFailed(String(localized: "Google Drive did not return a refresh token."))
        }
        let expiresIn = payload.expiresIn ?? 3600
        let tokenType = payload.tokenType?.isEmpty == false ? (payload.tokenType ?? "Bearer") : "Bearer"
        return GoogleDriveCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date.now.addingTimeInterval(TimeInterval(expiresIn)),
            tokenType: tokenType,
            accountEmail: existing?.accountEmail
        )
    }

    private static func authorizationURL(challenge: String, state: String) throws -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleDriveOAuthConfig.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleDriveOAuthConfig.authScope),
            URLQueryItem(name: "redirect_uri", value: GoogleDriveOAuthConfig.redirectURI),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        guard let url = components?.url else {
            throw GoogleDriveOAuthError.tokenExchangeFailed(String(localized: "Google Drive sign-in could not start."))
        }
        return url
    }

    private static func authorizationCode(from url: URL, expectedState: String) throws -> String {
        let items = queryItems(from: url)
        if let error = items.first(where: { $0.name == "error" })?.value {
            if error == "access_denied" {
                throw GoogleDriveOAuthError.cancelled
            }
            let description = items.first(where: { $0.name == "error_description" })?.value ?? error
            throw GoogleDriveOAuthError.tokenExchangeFailed(description)
        }
        let state = items.first(where: { $0.name == "state" })?.value
        guard state == expectedState else {
            throw GoogleDriveOAuthError.stateMismatch
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, code.isEmpty == false else {
            throw GoogleDriveOAuthError.invalidCallback
        }
        return code
    }

    private static func queryItems(from url: URL) -> [URLQueryItem] {
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            return items
        }
        guard let query = url.query, query.isEmpty == false else { return [] }
        return URLComponents(string: "https://invalid.example?\(query)")?.queryItems ?? []
    }

    private static func randomBase64URL(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw GoogleDriveOAuthError.tokenExchangeFailed(
                String(localized: "Google Drive sign-in could not start.")
            )
        }
        return Data(bytes).googleDriveBase64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).googleDriveBase64URLEncodedString()
    }

    private static func formBody(_ pairs: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = pairs.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private static func fallbackMessage(from data: Data, status: Int) -> String {
        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           text.isEmpty == false {
            return text
        }
        return "HTTP \(status)"
    }
}

private final class GoogleDriveAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let window: Any?

    init(window: Any?) {
        self.window = window
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        if let window = window as? UIWindow {
            return window
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        if let keyWindow = windows.first(where: \.isKeyWindow) ?? windows.first {
            return keyWindow
        }
        if let scene = scenes.first {
            return UIWindow(windowScene: scene)
        }
        if let fallbackScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return UIWindow(windowScene: fallbackScene)
        }
        preconditionFailure("Google Drive sign-in needs a window.")
        #elseif os(macOS)
        if let window = window as? NSWindow {
            return window
        }
        if let keyWindow = NSApplication.shared.keyWindow
            ?? NSApplication.shared.mainWindow
            ?? NSApplication.shared.windows.first(where: \.isVisible)
            ?? NSApplication.shared.windows.first {
            return keyWindow
        }
        preconditionFailure("Google Drive sign-in needs a window.")
        #endif
    }
}

nonisolated private final class GoogleDriveAuthContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?

    init(_ continuation: CheckedContinuation<URL, Error>) {
        self.continuation = continuation
    }

    func resume(callbackURL: URL?, error: Error?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        guard let pending else { return }

        if let error {
            pending.resume(throwing: Self.mapped(error))
            return
        }
        guard let callbackURL else {
            pending.resume(throwing: GoogleDriveOAuthError.invalidCallback)
            return
        }
        pending.resume(returning: callbackURL)
    }

    private static func mapped(_ error: Error) -> Error {
        if let authError = error as? ASWebAuthenticationSessionError,
           authError.code == .canceledLogin {
            return GoogleDriveOAuthError.cancelled
        }
        let nsError = error as NSError
        if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
           nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
            return GoogleDriveOAuthError.cancelled
        }
        if let oauthError = error as? GoogleDriveOAuthError {
            return oauthError
        }
        return error
    }
}

private struct GoogleDriveTokenResponse: Decodable {
    var accessToken: String?
    var refreshToken: String?
    var expiresIn: Int?
    var tokenType: String?
    var error: String?
    var errorDescription: String?

    var userFacingMessage: String? {
        if let errorDescription, errorDescription.isEmpty == false { return errorDescription }
        if let error, error.isEmpty == false { return error }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case error
        case errorDescription = "error_description"
    }
}

private extension Data {
    func googleDriveBase64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
