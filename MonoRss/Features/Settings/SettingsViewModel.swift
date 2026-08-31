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
    let progress = RefreshProgress()
    var isConnectingFreshRSS = false
    var isConfirmingDisconnect = false
    var isImportingOPML = false
    var isExportingOPML = false
    var statusMessage: String?

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

    func configure(with context: ModelContext) { self.context = context; reload() }
    func reload() {
        guard let context else { return }
        accounts = (try? context.fetch(FetchDescriptor<SyncAccount>())) ?? []
        feeds = (try? context.fetch(FetchDescriptor<Feed>(sortBy: [SortDescriptor(\.title)]))) ?? []
    }
    func sync() async {
        guard let context, let account = freshRSS else { return }
        isSyncing = true
        defer {
            progress.finish()
            isSyncing = false
        }
        do { try await freshRSSService.sync(account: account, in: context, progress: progress); statusMessage = "FreshRSS is up to date."; reload() }
        catch { statusMessage = RefreshFailure.message(for: error) ?? error.localizedDescription }
    }
    func disconnect() async {
        guard let context, let account = freshRSS else { return }
        do { try await freshRSSService.disconnect(account: account, in: context); statusMessage = "FreshRSS disconnected."; reload() }
        catch { statusMessage = error.localizedDescription }
    }
    func seedTinyRSSCatalog() {
        guard let context else { return }
        do {
            let result = try FeedSeedService().apply(in: context)
            UserDefaults.standard.set(true, forKey: AppPreferenceKey.didSeedTinyRSSCatalog)
            if result.inserted == 0 && result.updated == 0 && result.removed == 0 {
                statusMessage = "Starter sources are already loaded."
                reload()
                return
            }
            statusMessage = "Loaded \(result.inserted) starter source\(result.inserted == 1 ? "" : "s"). Updating…"
            reload()
            Task {
                if freshRSS != nil {
                    try? await freshRSSService.subscribeLocalFeeds(in: context)
                }
                await refreshImportedSources(importedCount: result.inserted)
            }
        } catch { statusMessage = error.localizedDescription }
    }

    func importOPML(from url: URL) {
        guard let context else { return }
        do {
            guard url.startAccessingSecurityScopedResource() else { throw OPMLServiceError.invalidDocument }
            defer { url.stopAccessingSecurityScopedResource() }
            let count = try OPMLService().importDocument(Data(contentsOf: url), in: context)
            statusMessage = "Imported \(count) source\(count == 1 ? "" : "s"). Updating…"
            reload()
            Task {
                if freshRSS != nil {
                    try? await freshRSSService.subscribeLocalFeeds(in: context)
                }
                await refreshImportedSources(importedCount: count)
            }
        } catch { statusMessage = error.localizedDescription }
    }

    private func refreshImportedSources(importedCount: Int) async {
        guard let context else { return }
        do {
            try await feedService.refreshAll(in: context, progress: progress)
            progress.finish()
            statusMessage = "Imported \(importedCount) source\(importedCount == 1 ? "" : "s")."
            reload()
        } catch {
            progress.finish()
            statusMessage = RefreshFailure.message(for: error) ?? error.localizedDescription
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
        guard let url = FreshRSSConfiguration.normalizedServerURL(from: server) else {
            presentedError = "Enter a valid server address."
            return false
        }
        isConnecting = true
        do { _ = try await freshRSSService.connect(serverURL: url, username: username, password: apiPassword, in: context); return true }
        catch { presentedError = error.localizedDescription; isConnecting = false; return false }
    }
}
