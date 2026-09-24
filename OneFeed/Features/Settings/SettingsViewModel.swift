import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class SettingsViewModel {
    private var context: ModelContext?
    private let freshRSSService: any FreshRSSSyncing
    private let feedService: any FeedRepository
    private(set) var accounts: [SyncAccount] = []
    private(set) var feeds: [Feed] = []
    private(set) var isSyncing = false
    private var isDisconnecting = false
    let progress = RefreshProgress()
    var isConnectingFreshRSS = false
    var isConfirmingDisconnect = false
    var isImportingOPML = false
    private var isStagingOPML = false
    var isExportingOPML = false
    var isConfirmingOPMLImport = false
    var statusTitle: String?
    var statusMessage = ""
    private(set) var opmlImportConfirmation = ""
    private var pendingOPMLPreview: OPMLImportPreview?
    private(set) var isLinkingGoogleDrive = false

    init() {
        freshRSSService = FreshRSSSyncService()
        feedService = FeedService()
    }

    init(freshRSSService: any FreshRSSSyncing, feedService: any FeedRepository) {
        self.freshRSSService = freshRSSService
        self.feedService = feedService
    }

    var freshRSS: SyncAccount? { accounts.first(where: { $0.provider == .freshRSS }) }
    var exportDocument: OPMLDocument { OPMLService().exportDocument(feeds: feeds) }

    func presentStatus(_ title: String, message: String = "") {
        statusTitle = title
        statusMessage = message
    }

    func clearStatus() {
        statusTitle = nil
        statusMessage = ""
    }

    /// Keeps the context for later edits. Accounts and feeds load when those screens appear.
    func configure(with context: ModelContext) {
        self.context = context
    }
    func reload() {
        guard let context else { return }
        accounts = (try? context.fetch(FetchDescriptor<SyncAccount>())) ?? []
        feeds = (try? context.fetch(FetchDescriptor<Feed>(sortBy: [SortDescriptor(\.title)]))) ?? []
    }
    func sync() async {
        guard !isSyncing, !isDisconnecting else { return }
        guard let context, let account = freshRSS else { return }
        isSyncing = true
        defer {
            progress.finish()
            isSyncing = false
        }
        do {
            try await freshRSSService.sync(account: account, in: context, progress: progress)
            presentStatus("FreshRSS is up to date")
            reload()
        } catch {
            guard UserFacingFailure.shouldSurface(error) else { return }
            presentStatus("Couldn’t refresh", message: UserFacingFailure.message(for: error, fallback: "Try again in a moment."))
        }
    }
    func disconnect() async {
        guard !isDisconnecting else { return }
        guard let context, let account = freshRSS else { return }
        isDisconnecting = true
        defer { isDisconnecting = false }
        do {
            try await freshRSSService.disconnect(account: account, in: context)
            presentStatus("FreshRSS disconnected")
            reload()
        } catch {
            presentStatus("Couldn’t disconnect", message: UserFacingFailure.message(for: error, fallback: "FreshRSS is still connected."))
        }
    }
    func seedAllCatalogSources() {
        guard let context else { return }
        do {
            let result = try FeedSeedService().apply(in: context)
            UserDefaults.standard.set(true, forKey: AppPreferenceKey.didSeedTinyRSSCatalog)
            UserDefaults.standard.set(FeedSeedCatalog.version, forKey: AppPreferenceKey.seedCatalogVersion)
            if result.inserted == 0 && result.updated == 0 && result.removed == 0 {
                presentStatus("Sources already loaded", message: "All seeded sources are already loaded.")
                reload()
                return
            }
            LibraryChange.noteStructureChanged()
            let restored = result.inserted
            presentStatus(
                "Restored \(restored) source\(restored == 1 ? "" : "s")",
                message: "\(result.updated) updated. Fetching…"
            )
            reload()
            Task {
                if freshRSS != nil {
                    try? await freshRSSService.subscribeLocalFeeds(in: context)
                }
                await refreshImportedSources(importedCount: result.inserted)
            }
        } catch {
            presentStatus("Couldn’t restore sources", message: UserFacingFailure.message(for: error, fallback: "The reading pack could not be restored."))
        }
    }

    func seedTinyRSSCatalog() {
        seedAllCatalogSources()
    }

    func seedCuratedReadingPack() {
        guard let context else { return }
        do {
            let result = try FeedSeedService().applyCuratedReadingPack(in: context)
            if result.inserted == 0 && result.updated == 0 {
                presentStatus("Reading pack already loaded", message: "AI reading pack already loaded.")
                reload()
                return
            }
            let loaded = result.inserted
            presentStatus(
                "Loaded \(loaded) source\(loaded == 1 ? "" : "s")",
                message: "Updating…"
            )
            reload()
            Task {
                if freshRSS != nil {
                    try? await freshRSSService.subscribeLocalFeeds(in: context)
                }
                await refreshImportedSources(importedCount: result.inserted)
            }
        } catch {
            presentStatus("Couldn’t load reading pack", message: UserFacingFailure.message(for: error, fallback: "The reading pack could not be loaded."))
        }
    }

    func beginLinkGoogleDrive() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-uiTesting") || arguments.contains("-inMemoryStore") { return }
        guard GoogleDriveOAuthConfig.isConfigured else {
            presentStatus("Couldn’t link Google Drive", message: "Google Drive is not configured on this build.")
            return
        }
        guard isLinkingGoogleDrive == false else { return }
        isLinkingGoogleDrive = true
        Task {
            defer { isLinkingGoogleDrive = false }
            do {
                try await linkGoogleDrive(
                    using: GoogleDriveAPIClient.shared,
                    snapshot: { [weak self] in
                        guard let context = self?.context else {
                            throw GoogleDriveLinkError.libraryUnavailable
                        }
                        return try await SwiftDataIngest.actor(from: context).encodedLibraryFile(
                            extraTombstones: LibraryFolderStore.loadTombstones()
                        )
                    }
                )
            } catch {
                presentStatus("Couldn’t link Google Drive", message: UserFacingFailure.message(for: error, fallback: "Google Drive could not be linked."))
            }
        }
    }

    /// Settings owns find-or-create. The library service only persists the link.
    func linkGoogleDrive(
        using drive: any GoogleDriveAPIClienting,
        signIn: () async throws -> GoogleDriveCredentials = {
            try await GoogleDriveOAuthClient.shared.signIn(from: nil)
        },
        snapshot: () async throws -> Data,
        library: any GoogleDriveLibraryLinking = LibrarySyncService.shared
    ) async throws {
        let credentials = try await signIn()
        let accountEmail: String?
        if let existingEmail = credentials.accountEmail, existingEmail.isEmpty == false {
            accountEmail = existingEmail
        } else {
            accountEmail = try? await drive.accountEmail()
        }
        if let existing = try await drive.findBackupFile() {
            let displayName = existing.name.isEmpty
                ? GoogleDriveOAuthConfig.backupFileName
                : existing.name
            library.linkGoogleDrive(
                fileID: existing.id,
                displayName: displayName,
                accountEmail: accountEmail,
                lastSyncedHash: nil
            )
            _ = await library.sync(request: .manual)
        } else {
            let data = try await snapshot()
            let created = try await drive.createBackupFile(
                data: data,
                name: GoogleDriveOAuthConfig.backupFileName
            )
            let displayName = created.name.isEmpty
                ? GoogleDriveOAuthConfig.backupFileName
                : created.name
            library.linkGoogleDrive(
                fileID: created.id,
                displayName: displayName,
                accountEmail: accountEmail,
                lastSyncedHash: CloudFileContentHash.sha256Hex(data)
            )
        }
    }

    /// Parses the picked file once and keeps the preview until Import or Cancel.
    func stageOPMLImport(from url: URL) {
        guard let context, !isStagingOPML else { return }
        isStagingOPML = true
        do {
            guard url.startAccessingSecurityScopedResource() else { throw OPMLServiceError.invalidDocument }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            Task {
                defer { isStagingOPML = false }
                do {
                    let outlines = try await Task.detached {
                        try OPMLService.parse(data)
                    }.value
                    let preview = try OPMLService().preview(outlines: outlines, in: context)
                    pendingOPMLPreview = preview
                    opmlImportConfirmation = preview.confirmationMessage
                    isConfirmingOPMLImport = true
                } catch {
                    presentStatus("Couldn’t import", message: UserFacingFailure.message(for: error, fallback: "That file could not be imported."))
                }
            }
        } catch {
            isStagingOPML = false
            presentStatus("Couldn’t import", message: UserFacingFailure.message(for: error, fallback: "That file could not be imported."))
        }
    }

    func acceptOPMLImport() {
        guard let preview = pendingOPMLPreview else { return }
        pendingOPMLPreview = nil
        commitOPMLImport(preview)
    }

    func declineOPMLImport() {
        pendingOPMLPreview = nil
    }

    private func commitOPMLImport(_ preview: OPMLImportPreview) {
        guard let context else { return }
        let outlines = preview.outlines
        Task {
            do {
                let applied = try await SwiftDataIngest.actor(from: context).importOPML(outlines)
                if applied.newSources > 0 || applied.folderMembershipsAdded > 0 {
                    LibraryChange.noteStructureChanged()
                }
                reload()
                if freshRSS != nil {
                    try? await freshRSSService.subscribeLocalFeeds(in: context)
                }
                await finishOPMLImport(newSourceCount: applied.newSources, folderMembershipsAdded: applied.folderMembershipsAdded)
            } catch {
                presentStatus("Couldn’t import", message: UserFacingFailure.message(for: error, fallback: "That file could not be imported."))
            }
        }
    }

    private func finishOPMLImport(newSourceCount: Int, folderMembershipsAdded: Int) async {
        guard let context else {
            presentStatus(
                OPMLImportPreview.resultTitle(newSourceCount: newSourceCount),
                message: OPMLImportPreview.resultMessage(folderMembershipsAdded: folderMembershipsAdded, refreshError: nil)
            )
            return
        }
        var refreshError: String?
        do {
            try await feedService.refreshAll(in: context, progress: progress)
            progress.finish()
            reload()
        } catch {
            progress.finish()
            if UserFacingFailure.shouldSurface(error) {
                refreshError = UserFacingFailure.message(for: error, fallback: "Try again in a moment.")
            }
        }
        presentStatus(
            OPMLImportPreview.resultTitle(newSourceCount: newSourceCount),
            message: OPMLImportPreview.resultMessage(folderMembershipsAdded: folderMembershipsAdded, refreshError: refreshError)
        )
    }

    private func refreshImportedSources(importedCount: Int) async {
        guard let context else { return }
        do {
            try await feedService.refreshAll(in: context, progress: progress)
            progress.finish()
            presentStatus("Imported \(importedCount) source\(importedCount == 1 ? "" : "s")")
            reload()
        } catch {
            progress.finish()
            guard UserFacingFailure.shouldSurface(error) else { return }
            presentStatus("Couldn’t refresh", message: UserFacingFailure.message(for: error, fallback: "Try again in a moment."))
        }
    }
}

@MainActor
@Observable
final class FreshRSSConnectViewModel {
    private let freshRSSService: any FreshRSSSyncing
    var server: String
    var username: String
    var apiPassword = ""
    private(set) var isConnecting = false
    var presentedError: String?

    init(existingAccount: SyncAccount?, freshRSSService: (any FreshRSSSyncing)? = nil) {
        self.freshRSSService = freshRSSService ?? FreshRSSSyncService()
        server = existingAccount?.serverURL?.absoluteString ?? ""
        username = existingAccount?.username ?? ""
    }

    func connect(in context: ModelContext) async -> Bool {
        guard !isConnecting else { return false }
        guard let url = FreshRSSConfiguration.normalizedServerURL(from: server) else {
            presentedError = "Enter a valid server address."
            return false
        }
        isConnecting = true
        defer { isConnecting = false }
        do {
            _ = try await freshRSSService.connect(serverURL: url, username: username, password: apiPassword, in: context)
            return true
        } catch {
            presentedError = UserFacingFailure.message(for: error, fallback: "Couldn’t connect to FreshRSS.")
            return false
        }
    }
}

@MainActor
protocol GoogleDriveLibraryLinking: AnyObject {
    func linkGoogleDrive(fileID: String, displayName: String, accountEmail: String?, lastSyncedHash: String?)
    func sync(request: LibrarySyncService.Request) async -> LibrarySyncService.Outcome
}

extension LibrarySyncService: GoogleDriveLibraryLinking {}

private enum GoogleDriveLinkError: Error, LocalizedError {
    case libraryUnavailable

    var errorDescription: String? {
        "The library could not be prepared for Google Drive."
    }
}
