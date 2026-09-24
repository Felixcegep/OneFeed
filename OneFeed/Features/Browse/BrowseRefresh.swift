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
    /// Clock time, not a relative phrase. A relative phrase changes as minutes pass, and each progress tick redraws the title bar.
    private(set) var statusText = "Pull to update"
    private var statusDay: Date?
    private var statusStamp: Date?

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
            self.recordRefreshTime(.now)
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

    func adoptLatestFetch(from feeds: [Feed], now: Date = .now) {
        if lastRefreshedAt == nil {
            lastRefreshedAt = feeds.compactMap(\.lastFetchedAt).max()
        }
        noteVisibleDay(now: now)
    }

    /// Republishes the subtitle when the calendar day changes. A refresh in progress keeps the line that was already showing.
    func noteVisibleDay(now: Date = .now, calendar: Calendar = .current) {
        guard !isRefreshing else { return }
        let day = calendar.startOfDay(for: now)
        guard statusDay != day || statusStamp != lastRefreshedAt else { return }
        publishStatus(now: now, calendar: calendar)
    }

    private func recordRefreshTime(_ date: Date, now: Date = .now) {
        lastRefreshedAt = date
        publishStatus(now: now)
    }

    private func publishStatus(now: Date, calendar: Calendar = .current) {
        statusDay = calendar.startOfDay(for: now)
        statusStamp = lastRefreshedAt
        statusText = Self.updatedLine(at: lastRefreshedAt, now: now, calendar: calendar)
    }

    /// Same-day updates use a clock time, so the title bar does not grow from “just now” to “1 minute ago” while the progress line moves.
    static func updatedLine(at date: Date?, now: Date = .now, calendar: Calendar = .current) -> String {
        guard let date else { return "Pull to update" }
        if calendar.isDate(date, inSameDayAs: now) {
            return "Updated \(date.formatted(date: .omitted, time: .shortened))"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Updated yesterday"
        }
        return "Updated \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}
