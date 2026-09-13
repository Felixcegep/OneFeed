import Foundation

nonisolated enum GoogleDriveOAuthConfig {
    static let authScope = "https://www.googleapis.com/auth/drive.file"
    static let backupFileName = "OneFeed.library.json"

    static var clientID: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "GoogleDriveClientID") as? String ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var isConfigured: Bool {
        isConfiguredClientID(clientID)
    }

    static var callbackURLScheme: String {
        reversedClientID(from: clientID)
    }

    static var redirectURI: String {
        callbackURLScheme + ":/oauth2redirect"
    }

    static func isConfiguredClientID(_ clientID: String) -> Bool {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty == false
            && trimmed.hasSuffix(".apps.googleusercontent.com")
            && trimmed.contains("REPLACE") == false
    }

    /// `123-abc.apps.googleusercontent.com` → `com.googleusercontent.apps.123-abc`
    static func reversedClientID(from clientID: String) -> String {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = ".apps.googleusercontent.com"
        guard trimmed.hasSuffix(suffix) else { return trimmed }
        let prefix = String(trimmed.dropLast(suffix.count))
        return "com.googleusercontent.apps.\(prefix)"
    }
}
