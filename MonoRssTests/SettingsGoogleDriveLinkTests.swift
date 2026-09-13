import Foundation
import Testing
@testable import OneFeed

@Suite(.serialized)
@MainActor
struct SettingsGoogleDriveLinkTests {
    @Test func openingExistingFileLinksWithoutHashAndRequestsManualSync() async throws {
        let drive = SettingsDriveFake()
        drive.existingFile = GoogleDriveFile(id: "file-1", name: "", md5Checksum: "ignore")
        let spy = SpyGoogleDriveLibraryLink()
        let viewModel = SettingsViewModel()
        let snapshot = Data("should-not-upload".utf8)

        try await viewModel.linkGoogleDrive(
            using: drive,
            signIn: { Self.credentials(email: "user@example.com") },
            snapshot: { snapshot },
            library: spy
        )

        #expect(spy.links.count == 1)
        #expect(spy.links.first?.fileID == "file-1")
        #expect(spy.links.first?.displayName == GoogleDriveOAuthConfig.backupFileName)
        #expect(spy.links.first?.accountEmail == "user@example.com")
        #expect(spy.links.first?.lastSyncedHash == nil)
        #expect(spy.syncRequests == [.manual])
        #expect(drive.createdPayloads.isEmpty)
        #expect(drive.didAskForAccountEmail == false)
    }

    @Test func creatingFileStoresBodyHashAndDoesNotSync() async throws {
        let drive = SettingsDriveFake()
        let spy = SpyGoogleDriveLibraryLink()
        let viewModel = SettingsViewModel()
        let snapshot = Data(#"{"schemaVersion":1}"#.utf8)

        try await viewModel.linkGoogleDrive(
            using: drive,
            signIn: { Self.credentials(email: nil) },
            snapshot: { snapshot },
            library: spy
        )

        #expect(spy.links.count == 1)
        #expect(spy.links.first?.fileID == "created-1")
        #expect(spy.links.first?.displayName == GoogleDriveOAuthConfig.backupFileName)
        #expect(spy.links.first?.accountEmail == "api@example.com")
        #expect(spy.links.first?.lastSyncedHash == CloudFileContentHash.sha256Hex(snapshot))
        #expect(spy.syncRequests.isEmpty)
        #expect(drive.createdPayloads == [snapshot])
        #expect(drive.didAskForAccountEmail)
    }

    private static func credentials(email: String?) -> GoogleDriveCredentials {
        GoogleDriveCredentials(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: .distantFuture,
            tokenType: "Bearer",
            accountEmail: email
        )
    }
}

@MainActor
private final class SpyGoogleDriveLibraryLink: GoogleDriveLibraryLinking {
    struct LinkCall: Equatable {
        var fileID: String
        var displayName: String
        var accountEmail: String?
        var lastSyncedHash: String?
    }

    var links: [LinkCall] = []
    var syncRequests: [LibrarySyncService.Request] = []

    func linkGoogleDrive(fileID: String, displayName: String, accountEmail: String?, lastSyncedHash: String?) {
        links.append(
            LinkCall(
                fileID: fileID,
                displayName: displayName,
                accountEmail: accountEmail,
                lastSyncedHash: lastSyncedHash
            )
        )
    }

    func sync(request: LibrarySyncService.Request) async -> LibrarySyncService.Outcome {
        syncRequests.append(request)
        return .unlinked
    }
}

private final class SettingsDriveFake: GoogleDriveAPIClienting, @unchecked Sendable {
    var existingFile: GoogleDriveFile?
    var createdFile = GoogleDriveFile(id: "created-1", name: "", md5Checksum: "md5")
    var email: String? = "api@example.com"
    private(set) var createdPayloads: [Data] = []
    private(set) var didAskForAccountEmail = false

    func findBackupFile() async throws -> GoogleDriveFile? { existingFile }

    func createBackupFile(data: Data, name: String) async throws -> GoogleDriveFile {
        createdPayloads.append(data)
        return createdFile
    }

    func downloadFile(id: String) async throws -> Data { Data() }

    func uploadFile(id: String, data: Data) async throws {}

    func accountEmail() async throws -> String? {
        didAskForAccountEmail = true
        return email
    }
}
