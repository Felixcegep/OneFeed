import BackgroundTasks
import Foundation
import SwiftData

@MainActor
enum BackgroundRefreshCoordinator {
    static let identifier = "felix.MonoRss.feed-refresh"
    static let staleInterval: TimeInterval = 15 * 60

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = .now.addingTimeInterval(30 * 60)
        do { try BGTaskScheduler.shared.submit(request) }
        catch { /* The system may reject duplicate or unavailable refresh requests. */ }
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
        do { try await feedService.refreshAll(in: context) } catch {}
        let freshRSS = SyncProvider.freshRSS.rawValue
        if let account = try? context.fetch(FetchDescriptor<SyncAccount>(predicate: #Predicate { $0.providerRawValue == freshRSS && $0.isEnabled })).first {
            try? await freshRSSService.sync(account: account, in: context, progress: nil)
        }
        _ = try? DailyDeckService().generateIfNeeded(in: context)
        _ = try? ArticleRetentionService().purge(in: context)
        let current = try? DailyDeckService().currentItem(in: context)
        await ArticleExtractionService().enrichUpcoming(in: context, from: current)
        lastSuccessfulRefresh = .now
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
