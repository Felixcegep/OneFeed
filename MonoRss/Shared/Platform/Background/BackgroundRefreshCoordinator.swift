import BackgroundTasks
import Foundation
import SwiftData

@MainActor
enum BackgroundRefreshCoordinator {
    static let identifier = "felix.MonoRss.feed-refresh"

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
            try? await freshRSSService.sync(account: account, in: context)
        }
        _ = try? ArticleQueueService().ensureCurrent(in: context)
    }
}
