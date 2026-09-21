import Foundation
import Security

nonisolated struct GoogleDriveCredentials: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var tokenType: String
    var accountEmail: String?
}

nonisolated struct GoogleDriveTokenStore: Sendable {
    static let shared = GoogleDriveTokenStore()

    private let service: String
    private let account: String

    init(
        service: String = "felix.MonoRss.googleDriveOAuth",
        account: String = "credentials"
    ) {
        self.service = service
        self.account = account
    }

    func load() -> GoogleDriveCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(GoogleDriveCredentials.self, from: data)
    }

    func save(_ credentials: GoogleDriveCredentials) throws {
        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            data = try encoder.encode(credentials)
        } catch {
            throw GoogleDriveTokenStoreError.unwritable(errSecParam)
        }
        delete()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw GoogleDriveTokenStoreError.unwritable(status) }
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

nonisolated enum GoogleDriveTokenStoreError: Error, Equatable, LocalizedError, Sendable {
    case unwritable(OSStatus)

    var errorDescription: String? {
        String(localized: "Google Drive credentials could not be saved on this device.")
    }
}
