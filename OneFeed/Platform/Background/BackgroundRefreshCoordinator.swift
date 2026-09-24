#if os(iOS)
import BackgroundTasks
#endif
import Foundation
import SwiftData

@MainActor
enum BackgroundRefreshCoordinator {
    static let identifier = "felix.MonoRss.feed-refresh"
    static let staleInterval: TimeInterval = 15 * 60
    private static var exclusiveRefresh: Task<Void, Never>?
    private static var enrichTask: Task<Void, Never>?
    /// Bumps when a refresh pass starts. A request that arrived during a pass runs once after it.
    private static var refreshGeneration = 0
    /// Bumps when an enrichment pass starts. The latest request during a pass runs once after it.
    private static var enrichGeneration = 0
    private static var pendingEnrich: (ModelContext, DailyDeckItem?, Int)?

    /// Lets Today, Feed, and scene-phase refresh share one in-flight update.
    /// A refresh that starts while one is running waits, then runs once so a source added mid-refresh is fetched.
    static func runExclusive(_ work: @escaping @MainActor () async -> Void) async {
        if exclusiveRefresh != nil {
            let seen = refreshGeneration
            while refreshGeneration == seen, let running = exclusiveRefresh {
                await running.value
            }
            if refreshGeneration == seen {
                await runExclusive(work)
            }
            return
        }
        refreshGeneration += 1
        let task = Task { @MainActor in
            defer { exclusiveRefresh = nil }
            await work()
        }
        exclusiveRefresh = task
        await task.value
    }

#if DEBUG
    static func resetExclusiveRefreshForTests() {
        exclusiveRefresh?.cancel()
        exclusiveRefresh = nil
        enrichTask?.cancel()
        enrichTask = nil
        refreshGeneration = 0
        enrichGeneration = 0
        pendingEnrich = nil
    }
#endif

    static func schedule() {
        #if os(iOS)
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = .now.addingTimeInterval(30 * 60)
        do { try BGTaskScheduler.shared.submit(request) }
        catch { /* The system may reject duplicate or unavailable refresh requests. */ }
        #endif
    }

    static func refresh(in context: ModelContext) async {
        await refresh(in: context, feedService: FeedService(), freshRSSService: FreshRSSSyncService())
        schedule()
    }

    static func refresh(
        in context: ModelContext,
        feedService: any FeedRepository,
        freshRSSService: any FreshRSSSyncing
    ) async {
        await runExclusive {
            do { try await feedService.refreshAll(in: context) } catch {}
            let freshRSS = SyncProvider.freshRSS.rawValue
            if let account = try? context.fetch(FetchDescriptor<SyncAccount>(predicate: #Predicate { $0.providerRawValue == freshRSS && $0.isEnabled })).first {
                try? await freshRSSService.sync(account: account, in: context, progress: nil)
            }
            try? await SwiftDataIngest.actor(from: context).finishToday()
            lastSuccessfulRefresh = .now
        }
        await enrichAfterRefresh(in: context)
        await LibrarySyncService.shared.flush()
    }

    /// One extraction-and-summary pass at a time. A second caller waits for that pass instead of starting another.
    static func enrichAfterRefresh(
        in context: ModelContext,
        from item: DailyDeckItem? = nil,
        extraQueued: Int = 0
    ) async {
        if enrichTask != nil {
            pendingEnrich = (context, item, extraQueued)
            let seen = enrichGeneration
            while enrichGeneration == seen, let running = enrichTask {
                await running.value
            }
            if enrichGeneration == seen, let pending = pendingEnrich {
                pendingEnrich = nil
                await enrichAfterRefresh(in: pending.0, from: pending.1, extraQueued: pending.2)
            }
            return
        }
        enrichGeneration += 1
        pendingEnrich = nil
        let task = Task(priority: .utility) {
            defer { enrichTask = nil }
            let current = item ?? (try? DailyDeckService().currentItem(in: context))
            await ArticleExtractionService().enrichUpcoming(in: context, from: current, extraQueued: extraQueued)
            await SemanticEnrichment.enrichUpcoming(in: context)
        }
        enrichTask = task
        await task.value
    }

    static var lastSuccessfulRefresh: Date? {
        get { UserDefaults.standard.object(forKey: AppPreferenceKey.lastSuccessfulRefresh) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: AppPreferenceKey.lastSuccessfulRefresh) }
    }

    static func refreshIfStale(in context: ModelContext, staleAfter: TimeInterval = staleInterval) async {
        guard let lastSuccessfulRefresh else { return }
        if Date().timeIntervalSince(lastSuccessfulRefresh) < staleAfter { return }
        await refresh(in: context)
    }
}
