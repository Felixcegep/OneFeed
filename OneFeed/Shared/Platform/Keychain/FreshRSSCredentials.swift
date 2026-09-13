import Foundation

#if canImport(Security)
import Security
#endif

public protocol FreshRSSCredentialStore: Sendable {
    func save(_ credentials: FreshRSSCredentials, for accountID: UUID) async throws
    func load(for accountID: UUID) async throws -> FreshRSSCredentials?
    func delete(for accountID: UUID) async throws
}

nonisolated public enum FreshRSSCredentialStoreError: Error, Equatable, Sendable {
    case unavailable
    case invalidData
    case operationFailed(OSStatus)
}

/// Keychain-backed credentials. No password or auth token is written to
/// SwiftData, UserDefaults, URLs, request query strings, or logs.
nonisolated public struct KeychainFreshRSSCredentialStore: FreshRSSCredentialStore, Sendable {
    private let service: String

    public init(service: String = "felix.MonoRss.freshrss") {
        self.service = service
    }

    public func save(_ credentials: FreshRSSCredentials, for accountID: UUID) async throws {
        #if canImport(Security)
        let data = try JSONEncoder().encode(PersistedCredentials(username: credentials.username, password: credentials.password))
        let query = baseQuery(accountID)
        let attributes: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else { throw FreshRSSCredentialStoreError.operationFailed(insertStatus) }
        } else if status != errSecSuccess {
            throw FreshRSSCredentialStoreError.operationFailed(status)
        }
        #else
        throw FreshRSSCredentialStoreError.unavailable
        #endif
    }

    public func load(for accountID: UUID) async throws -> FreshRSSCredentials? {
        #if canImport(Security)
        var query = baseQuery(accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw FreshRSSCredentialStoreError.operationFailed(status) }
        guard let data = result as? Data,
              let stored = try? JSONDecoder().decode(PersistedCredentials.self, from: data) else {
            throw FreshRSSCredentialStoreError.invalidData
        }
        return try FreshRSSCredentials(username: stored.username, password: stored.password)
        #else
        throw FreshRSSCredentialStoreError.unavailable
        #endif
    }

    public func delete(for accountID: UUID) async throws {
        #if canImport(Security)
        let status = SecItemDelete(baseQuery(accountID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw FreshRSSCredentialStoreError.operationFailed(status)
        }
        #else
        throw FreshRSSCredentialStoreError.unavailable
        #endif
    }

    #if canImport(Security)
    private func baseQuery(_ accountID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString
        ]
    }
    #endif

    private struct PersistedCredentials: Codable {
        let username: String
        let password: String
    }
}

public actor InMemoryFreshRSSCredentialStore: FreshRSSCredentialStore {
    private var values: [UUID: FreshRSSCredentials] = [:]

    public init() {}

    public func save(_ credentials: FreshRSSCredentials, for accountID: UUID) {
        values[accountID] = credentials
    }

    public func load(for accountID: UUID) -> FreshRSSCredentials? {
        values[accountID]
    }

    public func delete(for accountID: UUID) {
        values.removeValue(forKey: accountID)
    }
}
