import Foundation
import SwiftData
import Testing
@testable import OneFeed

@Suite(.serialized)
@MainActor
struct LibrarySyncServiceDriveTests {
    @Test func keepThisIPhoneWritesBytesToFakeClient() async throws {
        let harness = try DriveSyncHarness()
        defer { harness.tearDown() }

        let fileID = "drive-file-1"
        harness.service.linkGoogleDrive(
            fileID: fileID,
            displayName: "OneFeed.library.json",
            accountEmail: "reader@example.com"
        )

        let pushed = await harness.service.sync(request: .keepThisIPhone)
        #expect(pushed == .pushed)
        #expect(harness.service.lastOutcome == .pushed)
        #expect(harness.fake.files[fileID] != nil)
        #expect(harness.fake.files[fileID]?.isEmpty == false)
        #expect(harness.service.linkedRecord?.googleDriveFileID == fileID)
        #expect(harness.service.linkedRecord?.lastSyncedHash != nil)

        let expectedHash = CloudFileContentHash.sha256Hex(try LibrarySyncService.encodedLibraryFile(from: harness.context))
        #expect(harness.service.linkedRecord?.lastSyncedHash == expectedHash)
        #expect(harness.service.linkedRecord?.lastSyncedHash != harness.fake.md5Checksum)
    }

    @Test func ingestActorWritesTheSameLibraryFileAsTheOpenScreen() async throws {
        let harness = try DriveSyncHarness()
        defer { harness.tearDown() }
        let onScreen = try LibrarySyncService.encodedLibraryFile(from: harness.context)
        let onActor = try await SwiftDataIngest.actor(from: harness.context).encodedLibraryFile(
            extraTombstones: LibraryFolderStore.loadTombstones()
        )
        #expect(onActor == onScreen)
    }

    @Test func openExistingWithDifferentRemoteBytesConflictsInsteadOfPulling() async throws {
        let harness = try DriveSyncHarness()
        defer { harness.tearDown() }

        let fileID = "drive-file-open"
        harness.fake.files[fileID] = Data(#"{"schemaVersion":1,"not":"local"}"#.utf8)
        harness.service.linkGoogleDrive(
            fileID: fileID,
            displayName: "OneFeed.library.json",
            accountEmail: nil
        )

        let outcome = await harness.service.sync(request: .manual)
        #expect(outcome == .conflict)
        #expect(harness.service.lastOutcome == .conflict)
        let feeds = try harness.context.fetch(FetchDescriptor<Feed>())
        #expect(feeds.isEmpty)
    }

    @Test func createStyleLinkStoresPushedHashAndFollowingSyncIsInSync() async throws {
        let harness = try DriveSyncHarness()
        defer { harness.tearDown() }

        let fileID = "drive-file-create"
        let uploaded = try LibrarySyncService.encodedLibraryFile(from: harness.context)
        let hash = CloudFileContentHash.sha256Hex(uploaded)
        harness.fake.files[fileID] = uploaded
        harness.fake.md5Checksum = "not-the-sha256-of-the-json-body"

        harness.service.linkGoogleDrive(
            fileID: fileID,
            displayName: "OneFeed.library.json",
            accountEmail: "reader@example.com",
            lastSyncedHash: hash
        )

        #expect(harness.service.lastOutcome == .pushed)
        #expect(harness.service.linkedRecord?.lastSyncedHash == hash)
        #expect(harness.service.linkedRecord?.lastSyncedAt != nil)

        let again = await harness.service.sync(request: .manual)
        #expect(again == .inSync)
        #expect(harness.service.linkedRecord?.lastSyncedHash == hash)
        #expect(harness.service.linkedRecord?.lastSyncedHash != harness.fake.md5Checksum)
    }

    @Test func hashIsSha256OfJSONBodyAndIgnoresDriveMd5Checksum() async throws {
        let harness = try DriveSyncHarness()
        defer { harness.tearDown() }

        let fileID = "drive-file-hash"
        harness.fake.md5Checksum = "ffffffffffffffffffffffffffffffff"
        harness.service.linkGoogleDrive(
            fileID: fileID,
            displayName: "OneFeed.library.json",
            accountEmail: nil
        )

        let pushed = await harness.service.sync(request: .keepThisIPhone)
        #expect(pushed == .pushed)
        let body = try #require(harness.fake.files[fileID])
        let sha = CloudFileContentHash.sha256Hex(body)
        #expect(harness.service.linkedRecord?.lastSyncedHash == sha)
        #expect(sha != harness.fake.md5Checksum)

        let listed = try await harness.fake.findBackupFile()
        #expect(listed?.md5Checksum == harness.fake.md5Checksum)

        let again = await harness.service.sync(request: .manual)
        #expect(again == .inSync)
    }

    @Test func autoSyncDisabledWhenModeIsManual() {
        let harness = DriveSyncHarness.makeUnconfigured()
        defer { harness.tearDown() }

        harness.service.linkGoogleDrive(
            fileID: "drive-file-3",
            displayName: "OneFeed.library.json",
            accountEmail: "reader@example.com"
        )
        #expect(harness.service.isLinked)
        #expect(harness.service.isAutoSyncEnabled)

        harness.service.setSyncMode(.manual)
        #expect(harness.service.linkedRecord?.syncMode == .manual)
        #expect(harness.service.isAutoSyncEnabled == false)
        #expect(harness.service.isLinked)
    }

    @Test func pullSkippedWhenReadingSessionIsActiveForAutomaticAndManual() async throws {
        let harness = try DriveSyncHarness()
        defer { harness.tearDown() }

        let fileID = "drive-file-skip"
        harness.service.linkGoogleDrive(
            fileID: fileID,
            displayName: "OneFeed.library.json",
            accountEmail: nil
        )
        #expect(await harness.service.sync(request: .keepThisIPhone) == .pushed)
        let pushedHash = try #require(harness.service.linkedRecord?.lastSyncedHash)

        harness.fake.files[fileID] = try remoteLibraryBytes()
        #expect(CloudFileContentHash.sha256Hex(harness.fake.files[fileID]!) != pushedHash)

        harness.service.hasActiveReadingSession = true
        #expect(await harness.service.sync(request: .automatic) == .skippedActiveSession)
        #expect(await harness.service.sync(request: .manual) == .skippedActiveSession)
        #expect(harness.service.linkedRecord?.lastSyncedHash == pushedHash)
        let feeds = try harness.context.fetch(FetchDescriptor<Feed>())
        #expect(feeds.isEmpty)
    }

    @Test func skippedDrivePullRunsOnceAfterReadingEnds() async throws {
        let harness = try DriveSyncHarness()
        defer { harness.tearDown() }

        let fileID = "drive-file-skip-later"
        harness.service.linkGoogleDrive(
            fileID: fileID,
            displayName: "OneFeed.library.json",
            accountEmail: nil
        )
        #expect(await harness.service.sync(request: .keepThisIPhone) == .pushed)
        harness.fake.files[fileID] = try remoteLibraryBytes()
        harness.fake.downloadCount = 0

        harness.service.hasActiveReadingSession = true
        #expect(await harness.service.sync(request: .automatic) == .skippedActiveSession)
        #expect(await harness.service.sync(request: .manual) == .skippedActiveSession)
        #expect(harness.fake.downloadCount == 2)

        harness.service.hasActiveReadingSession = false
        var titles: [String] = []
        for _ in 0..<30 {
            titles = try harness.context.fetch(FetchDescriptor<Feed>()).map(\.title)
            if titles == ["Remote Source"] { break }
            await Task.yield()
        }
        #expect(titles == ["Remote Source"])
        let downloadsAfterPull = harness.fake.downloadCount
        for _ in 0..<8 {
            await Task.yield()
        }
        #expect(harness.fake.downloadCount == downloadsAfterPull)
    }

    @Test func drivePushWaitsUntilReadingEnds() async throws {
        let harness = try DriveSyncHarness()
        defer { harness.tearDown() }

        let fileID = "drive-file-push-wait"
        harness.service.linkGoogleDrive(
            fileID: fileID,
            displayName: "OneFeed.library.json",
            accountEmail: nil
        )
        #expect(await harness.service.sync(request: .keepThisIPhone) == .pushed)
        let pushed = try #require(harness.fake.files[fileID])

        harness.context.insert(Feed(title: "Local Source", feedURL: URL(string: "https://local.test/rss")!))
        harness.service.hasActiveReadingSession = true
        #expect(await harness.service.sync(request: .automatic) == .skippedActiveSession)
        #expect(await harness.service.sync(request: .manual) == .skippedActiveSession)
        #expect(harness.fake.files[fileID] == pushed)

        harness.service.hasActiveReadingSession = false
        var sent = false
        for _ in 0..<40 {
            if harness.fake.files[fileID] != pushed {
                sent = true
                break
            }
            await Task.yield()
        }
        #expect(sent)
        let body = try #require(harness.fake.files[fileID])
        #expect(String(decoding: body, as: UTF8.self).contains("Local Source"))
    }

    @Test func useCloudFileStillPullsDuringActiveReadingSession() async throws {
        let harness = try DriveSyncHarness()
        defer { harness.tearDown() }

        let fileID = "drive-file-force-pull"
        harness.service.linkGoogleDrive(
            fileID: fileID,
            displayName: "OneFeed.library.json",
            accountEmail: nil
        )
        #expect(await harness.service.sync(request: .keepThisIPhone) == .pushed)

        harness.fake.files[fileID] = try remoteLibraryBytes()
        harness.service.hasActiveReadingSession = true

        let pulled = await harness.service.sync(request: .useCloudFile)
        #expect(pulled == .pulled)
        let feeds = try harness.context.fetch(FetchDescriptor<Feed>())
        #expect(feeds.map(\.title) == ["Remote Source"])
    }

    @Test func missingRemoteFileDoesNotExistIsTreatedAsPush() async throws {
        let harness = try DriveSyncHarness()
        defer { harness.tearDown() }

        let fileID = "drive-file-missing"
        harness.service.linkGoogleDrive(
            fileID: fileID,
            displayName: "OneFeed.library.json",
            accountEmail: nil
        )

        let outcome = await harness.service.sync(request: .manual)
        #expect(outcome == .pushed)
        #expect(harness.fake.files[fileID] != nil)
        #expect(harness.fake.files[fileID]?.isEmpty == false)
        #expect(harness.service.linkedRecord?.lastSyncedHash != nil)
    }
}

@MainActor
private struct DriveSyncHarness {
    let suiteName: String
    let defaults: UserDefaults
    let fake: FakeGoogleDriveAPIClient
    let service: LibrarySyncService
    let context: ModelContext

    init() throws {
        let parts = Self.makeService()
        suiteName = parts.0
        defaults = parts.1
        fake = parts.2
        service = parts.3
        context = try InMemoryStore.makeContext()
        service.configure(with: context)
    }

    init(
        suiteName: String,
        defaults: UserDefaults,
        fake: FakeGoogleDriveAPIClient,
        service: LibrarySyncService,
        context: ModelContext
    ) {
        self.suiteName = suiteName
        self.defaults = defaults
        self.fake = fake
        self.service = service
        self.context = context
    }

    static func makeUnconfigured() -> DriveSyncHarness {
        let parts = makeService()
        return DriveSyncHarness(
            suiteName: parts.0,
            defaults: parts.1,
            fake: parts.2,
            service: parts.3,
            context: ModelContext(try! InMemoryStore.makeContainer())
        )
    }

    private static func makeService() -> (String, UserDefaults, FakeGoogleDriveAPIClient, LibrarySyncService) {
        let suiteName = "LibrarySyncServiceDriveTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let fake = FakeGoogleDriveAPIClient()
        let service = LibrarySyncService(defaults: defaults, googleDrive: fake)
        return (suiteName, defaults, fake, service)
    }

    func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private func remoteLibraryBytes() throws -> Data {
    let document = LibraryDocument(
        schemaVersion: LibraryDocumentFormat.schemaVersion,
        updatedAt: Date(timeIntervalSince1970: 50),
        folderNames: [],
        feeds: [
            LibraryFeed(
                feedURL: "https://remote.test/rss",
                title: "Remote Source",
                websiteURL: nil,
                folderName: nil,
                isEnabled: true,
                contentKind: "article",
                includeInToday: true,
                includeVideos: true,
                includeShorts: false,
                minVideoSeconds: 180,
                blockedWords: "",
                updatedAt: Date(timeIntervalSince1970: 40)
            )
        ],
        articles: [],
        tombstones: [],
        currentArticleKey: nil,
        currentUpdatedAt: nil
    )
    return try document.encoded()
}

private final class FakeGoogleDriveAPIClient: GoogleDriveAPIClienting, @unchecked Sendable {
    var files: [String: Data] = [:]
    var email: String? = "reader@example.com"
    var md5Checksum: String? = "ignored-md5-checksum"
    var downloadCount = 0

    func findBackupFile() async throws -> GoogleDriveFile? {
        guard let first = files.first else { return nil }
        return GoogleDriveFile(id: first.key, name: "OneFeed.library.json", md5Checksum: md5Checksum)
    }

    func createBackupFile(data: Data, name: String) async throws -> GoogleDriveFile {
        let id = UUID().uuidString
        files[id] = data
        return GoogleDriveFile(id: id, name: name, md5Checksum: md5Checksum)
    }

    func downloadFile(id: String) async throws -> Data {
        downloadCount += 1
        guard let data = files[id] else {
            throw URLError(.fileDoesNotExist)
        }
        return data
    }

    func uploadFile(id: String, data: Data) async throws {
        files[id] = data
    }

    func accountEmail() async throws -> String? {
        email
    }
}
