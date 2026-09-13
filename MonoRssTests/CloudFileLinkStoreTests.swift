import Foundation
import Testing
@testable import OneFeed

struct CloudFileLinkStoreTests {
    @Test func saveLoadRoundTrip() {
        let harness = LinkStoreHarness()
        defer { harness.tearDown() }

        let store = CloudFileLinkStore(defaults: harness.defaults)
        let syncedAt = Date(timeIntervalSince1970: 1_760_000_000)
        let record = CloudFileLinkRecord(
            bookmarkData: Data("bookmark-bytes".utf8),
            displayName: "OneFeed.library.json",
            locationKind: .iCloudDrive,
            lastSyncedHash: "abc123",
            lastSyncedAt: syncedAt
        )

        #expect(store.load() == nil)
        store.save(record)

        let loaded = store.load()
        #expect(loaded?.bookmarkData == record.bookmarkData)
        #expect(loaded?.displayName == record.displayName)
        #expect(loaded?.locationKind == record.locationKind)
        #expect(loaded?.lastSyncedHash == record.lastSyncedHash)
        #expect(loaded?.lastSyncedAt?.timeIntervalSince1970 == syncedAt.timeIntervalSince1970)
        #expect(loaded?.googleDriveFileID == nil)
        #expect(loaded?.googleDriveAccountEmail == nil)
        #expect(loaded?.syncMode == .automatic)
        #expect(loaded?.usesGoogleDriveAPI == false)
    }

    @Test func googleDriveFieldsRoundTrip() {
        let harness = LinkStoreHarness()
        defer { harness.tearDown() }

        let store = CloudFileLinkStore(defaults: harness.defaults)
        let record = CloudFileLinkRecord(
            bookmarkData: Data(),
            displayName: "OneFeed.library.json",
            locationKind: .googleDrive,
            lastSyncedHash: "drive-hash",
            lastSyncedAt: Date(timeIntervalSince1970: 1_760_000_000),
            googleDriveFileID: "file-123",
            googleDriveAccountEmail: "reader@example.com",
            syncMode: .manual
        )

        store.save(record)
        let loaded = store.load()
        #expect(loaded?.googleDriveFileID == "file-123")
        #expect(loaded?.googleDriveAccountEmail == "reader@example.com")
        #expect(loaded?.syncMode == .manual)
        #expect(loaded?.usesGoogleDriveAPI == true)
        #expect(loaded?.bookmarkData == Data())
    }

    @Test func legacyJSONDecodesAsAutomaticWithNilDriveIDs() throws {
        struct LegacyRecord: Encodable {
            var bookmarkData: Data
            var displayName: String
            var locationKind: CloudFileLocationKind
            var lastSyncedHash: String?
            var lastSyncedAt: Date?
        }

        let syncedAt = Date(timeIntervalSince1970: 1_760_000_000)
        let data = try JSONEncoder().encode(
            LegacyRecord(
                bookmarkData: Data("bookmark-bytes".utf8),
                displayName: "OneFeed.library.json",
                locationKind: .iCloudDrive,
                lastSyncedHash: "abc123",
                lastSyncedAt: syncedAt
            )
        )

        let decoded = try JSONDecoder().decode(CloudFileLinkRecord.self, from: data)
        #expect(decoded.bookmarkData == Data("bookmark-bytes".utf8))
        #expect(decoded.displayName == "OneFeed.library.json")
        #expect(decoded.locationKind == .iCloudDrive)
        #expect(decoded.lastSyncedHash == "abc123")
        #expect(decoded.lastSyncedAt?.timeIntervalSince1970 == syncedAt.timeIntervalSince1970)
        #expect(decoded.googleDriveFileID == nil)
        #expect(decoded.googleDriveAccountEmail == nil)
        #expect(decoded.syncMode == .automatic)
        #expect(decoded.usesGoogleDriveAPI == false)
    }

    @Test func clearRemovesRecord() {
        let harness = LinkStoreHarness()
        defer { harness.tearDown() }

        let store = CloudFileLinkStore(defaults: harness.defaults)
        store.save(
            CloudFileLinkRecord(
                bookmarkData: Data("bookmark".utf8),
                displayName: "OneFeed.library.json",
                locationKind: .googleDrive,
                lastSyncedHash: "hash",
                lastSyncedAt: Date(timeIntervalSince1970: 1_760_000_000)
            )
        )

        #expect(store.load() != nil)
        store.clear()
        #expect(store.load() == nil)
    }

    @Test func updateLastSyncRewritesHashAndDate() {
        let harness = LinkStoreHarness()
        defer { harness.tearDown() }

        let store = CloudFileLinkStore(defaults: harness.defaults)
        store.save(
            CloudFileLinkRecord(
                bookmarkData: Data("bookmark".utf8),
                displayName: "OneFeed.library.json",
                locationKind: .otherFiles,
                lastSyncedHash: "old-hash",
                lastSyncedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )

        let newDate = Date(timeIntervalSince1970: 1_760_050_000)
        store.updateLastSync(hash: "new-hash", at: newDate)

        let loaded = store.load()
        #expect(loaded?.bookmarkData == Data("bookmark".utf8))
        #expect(loaded?.displayName == "OneFeed.library.json")
        #expect(loaded?.locationKind == .otherFiles)
        #expect(loaded?.lastSyncedHash == "new-hash")
        #expect(loaded?.lastSyncedAt?.timeIntervalSince1970 == newDate.timeIntervalSince1970)
    }
}

private struct LinkStoreHarness {
    let suiteName: String
    let defaults: UserDefaults

    init() {
        suiteName = "CloudFileLinkStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
