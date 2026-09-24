import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class BrowseRefresh {
    private let feedService: any FeedRepository
    private let freshRSSService: any FreshRSSSyncing
    private var inFlight: Task<Void, Never>?
    private(set) var isRefreshing = false
    private(set) var lastRefreshedAt: Date?
    let progress = RefreshProgress()
    var presentedError: String?

    /// Stays put while a refresh runs. The progress line carries that status, so the title bar does not resize.
    var statusText: String {
        guard let lastRefreshedAt else { return "Pull to update" }
        return "Updated \(lastRefreshedAt.formatted(.relative(presentation: .named)))"
    }

    init() {
        self.feedService = FeedService()
        self.freshRSSService = FreshRSSSyncService()
    }

    init(
        feedService: any FeedRepository,
        freshRSSService: any FreshRSSSyncing
    ) {
        self.feedService = feedService
        self.freshRSSService = freshRSSService
    }

    func refresh(in context: ModelContext) async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { await self.runRefresh(in: context) }
        inFlight = task
        await task.value
    }

    private func runRefresh(in context: ModelContext) async {
        isRefreshing = true
        defer {
            progress.finish()
            isRefreshing = false
            inFlight = nil
        }
        await BackgroundRefreshCoordinator.runExclusive {
            await self.performRefreshWork(in: context)
            self.lastRefreshedAt = .now
        }
    }

    private func performRefreshWork(in context: ModelContext) async {
        var refreshError: Error?
        do { try await feedService.refreshAll(in: context, progress: progress) } catch { refreshError = error }
        let provider = SyncProvider.freshRSS.rawValue
        if let account = try? context.fetch(FetchDescriptor<SyncAccount>(predicate: #Predicate { $0.providerRawValue == provider && $0.isEnabled })).first {
            do { try await freshRSSService.sync(account: account, in: context, progress: progress) } catch { refreshError = refreshError ?? error }
        }
        progress.begin(phase: .finishing, total: 1)
        do {
            try await SwiftDataIngest.actor(from: context).finishToday()
            progress.finishItem(newArticles: 0)
        } catch {
            refreshError = refreshError ?? error
            progress.finishItem(newArticles: 0)
        }
        if let refreshError {
            presentedError = RefreshFailure.message(for: refreshError)
        } else {
            BackgroundRefreshCoordinator.lastSuccessfulRefresh = .now
        }
    }

    func adoptLatestFetch(from feeds: [Feed]) {
        guard lastRefreshedAt == nil else { return }
        lastRefreshedAt = feeds.compactMap(\.lastFetchedAt).max()
    }
}
