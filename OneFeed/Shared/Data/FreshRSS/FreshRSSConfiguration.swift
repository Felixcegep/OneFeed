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
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else {
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
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        var basePath = components.percentEncodedPath
        while basePath.hasSuffix("/") { basePath.removeLast() }
        var joined = basePath.isEmpty ? "/\(relativePath)" : "\(basePath)/\(relativePath)"
        while joined.hasSuffix("/") && joined != "/" { joined.removeLast() }
        components.percentEncodedPath = joined
        return components.url!
    }

    public static func normalizedServerURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), isUsableServerURL(url) {
            return normalizedServerURL(url)
        }
        return URL(string: "http://\(trimmed)").flatMap { isUsableServerURL($0) ? normalizedServerURL($0) : nil }
    }

    private static func normalizedServerURL(_ url: URL) -> URL? {
        let candidate: URL
        if isUsableServerURL(url) {
            candidate = url
        } else if url.scheme == nil, let host = url.absoluteString.nilIfEmpty {
            guard let parsed = URL(string: "http://\(host)"), isUsableServerURL(parsed) else { return nil }
            candidate = parsed
        } else {
            return nil
        }
        return strippingGReaderAPIPathSuffix(from: candidate)
    }

    /// Accepts a server root, a pasted GReader endpoint, or a full ClientLogin
    /// URL. The client always appends `api/greader.php/...` itself. Anything
    /// from that marker onward must be stripped — tiny-rss answers unknown
    /// GReader paths with HTTP 401, not 404.
    private static func strippingGReaderAPIPathSuffix(from url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var path = components.percentEncodedPath
        let lower = path.lowercased()
        let markers = ["/p/api/greader.php", "/api/greader.php", "/greader.php"]
        for marker in markers {
            if let range = lower.range(of: marker) {
                let offset = lower.distance(from: lower.startIndex, to: range.lowerBound)
                let cut = path.index(path.startIndex, offsetBy: offset)
                path = String(path[..<cut])
                break
            }
        }
        while path.hasSuffix("/") { path.removeLast() }

        if path.isEmpty {
            components.path = ""
        } else if !path.hasPrefix("/") {
            components.path = "/\(path)"
        } else {
            components.path = path
        }
        components.query = nil
        components.fragment = nil
        return components.url ?? url
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
