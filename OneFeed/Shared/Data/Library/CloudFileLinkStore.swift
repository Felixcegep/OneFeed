import Foundation

nonisolated enum CloudFileSyncMode: String, Codable, CaseIterable, Sendable {
    case manual
    case automatic

    var title: String {
        switch self {
        case .manual: String(localized: "Manual")
        case .automatic: String(localized: "Automatic")
        }
    }
}

/// Installation-local record of the linked Google Drive library file.
nonisolated struct CloudFileLinkRecord: Codable, Equatable, Sendable {
    var bookmarkData: Data
    var displayName: String
    var locationKind: CloudFileLocationKind
    var lastSyncedHash: String?
    var lastSyncedAt: Date?
    var googleDriveFileID: String?
    var googleDriveAccountEmail: String?
    var syncMode: CloudFileSyncMode

    var usesGoogleDriveAPI: Bool { googleDriveFileID?.isEmpty == false }

    enum CodingKeys: String, CodingKey {
        case bookmarkData
        case displayName
        case locationKind
        case lastSyncedHash
        case lastSyncedAt
        case googleDriveFileID
        case googleDriveAccountEmail
        case syncMode
    }

    init(
        bookmarkData: Data,
        displayName: String,
        locationKind: CloudFileLocationKind,
        lastSyncedHash: String? = nil,
        lastSyncedAt: Date? = nil,
        googleDriveFileID: String? = nil,
        googleDriveAccountEmail: String? = nil,
        syncMode: CloudFileSyncMode = .automatic
    ) {
        self.bookmarkData = bookmarkData
        self.displayName = displayName
        self.locationKind = locationKind
        self.lastSyncedHash = lastSyncedHash
        self.lastSyncedAt = lastSyncedAt
        self.googleDriveFileID = googleDriveFileID
        self.googleDriveAccountEmail = googleDriveAccountEmail
        self.syncMode = syncMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bookmarkData = try container.decode(Data.self, forKey: .bookmarkData)
        displayName = try container.decode(String.self, forKey: .displayName)
        locationKind = try container.decode(CloudFileLocationKind.self, forKey: .locationKind)
        lastSyncedHash = try container.decodeIfPresent(String.self, forKey: .lastSyncedHash)
        lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        googleDriveFileID = try container.decodeIfPresent(String.self, forKey: .googleDriveFileID)
        googleDriveAccountEmail = try container.decodeIfPresent(String.self, forKey: .googleDriveAccountEmail)
        syncMode = try container.decodeIfPresent(CloudFileSyncMode.self, forKey: .syncMode) ?? .automatic
    }
}

nonisolated struct CloudFileLinkStore {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = AppPreferenceKey.cloudFileLinkRecord
    ) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> CloudFileLinkRecord? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CloudFileLinkRecord.self, from: data)
    }

    func save(_ record: CloudFileLinkRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    func updateLastSync(hash: String, at date: Date = .now) {
        guard var record = load() else { return }
        record.lastSyncedHash = hash
        record.lastSyncedAt = date
        save(record)
    }
}
