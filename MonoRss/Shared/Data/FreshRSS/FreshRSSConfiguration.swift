import Foundation

/// The credentials needed by FreshRSS's Google Reader compatible API.
///
/// FreshRSS calls the password field `Passwd` in `ClientLogin`. Applications
/// should normally put an application password here rather than the user's
/// primary password.
nonisolated public struct FreshRSSCredentials: Sendable, Equatable {
    public let username: String
    public let password: String

    public init(username: String, password: String) throws {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FreshRSSError.invalidCredentials
        }
        guard !password.isEmpty else {
            throw FreshRSSError.invalidCredentials
        }
        self.username = username
        self.password = password
    }
}

nonisolated public struct FreshRSSConfiguration: Sendable, Equatable {
    public let baseURL: URL
    public let username: String

    /// - Parameters:
    ///   - baseURL: The FreshRSS installation URL, for example
    ///     `https://rss.example.com`, `http://rss.local`, or an IP on the LAN.
    ///   - username: The FreshRSS account username.
    public init(baseURL: URL, username: String) throws {
        guard let url = Self.normalizedServerURL(baseURL) else {
            throw FreshRSSError.invalidServerURL
        }
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FreshRSSError.invalidCredentials
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.path = components.path.isEmpty ? "" : components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !components.path.isEmpty { components.path = "/" + components.path }
        self.baseURL = components.url!
        self.username = username
    }

    public func endpoint(_ path: String) -> URL {
        let relativePath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return baseURL.appendingPathComponent(relativePath)
    }

    public static func normalizedServerURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), isUsableServerURL(url) { return url }
        return URL(string: "http://\(trimmed)").flatMap { isUsableServerURL($0) ? $0 : nil }
    }

    private static func normalizedServerURL(_ url: URL) -> URL? {
        if isUsableServerURL(url) { return url }
        guard url.scheme == nil, let host = url.absoluteString.nilIfEmpty else { return nil }
        return URL(string: "http://\(host)").flatMap { isUsableServerURL($0) ? $0 : nil }
    }

    private static func isUsableServerURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return false }
        return url.host != nil
    }
}

nonisolated public enum FreshRSSError: Error, Equatable, Sendable {
    case invalidServerURL
    case invalidCredentials
    case missingAuthToken
    case invalidResponse
    case httpStatus(Int, String?)
    case decodingFailed
    case unsupportedMutation
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
