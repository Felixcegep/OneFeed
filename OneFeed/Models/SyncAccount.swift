import Foundation
import SwiftData

enum SyncProvider: String, Codable, CaseIterable, Sendable {
    case local
    case freshRSS
}

@Model
final class SyncAccount {
    @Attribute(.unique) var id: UUID
    var providerRawValue: String
    var serverURL: URL?
    var username: String?
    var isEnabled: Bool
    var lastSyncAt: Date?
    var lastSyncError: String?

    var provider: SyncProvider {
        get { SyncProvider(rawValue: providerRawValue) ?? .local }
        set { providerRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        provider: SyncProvider = .local,
        serverURL: URL? = nil,
        username: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.providerRawValue = provider.rawValue
        self.serverURL = serverURL
        self.username = username
        self.isEnabled = isEnabled
    }
}
