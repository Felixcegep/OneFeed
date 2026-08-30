import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class BrowseRefresh {
    private let feedService: any FeedRepository
    private let freshRSSService: any FreshRSSSyncing
    private(set) var isRefreshing = false
    var presentedError: String?

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
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        var refreshError: Error?
        do { try await feedService.refreshAll(in: context) } catch { refreshError = error }
        let provider = SyncProvider.freshRSS.rawValue
        if let account = try? context.fetch(FetchDescriptor<SyncAccount>(predicate: #Predicate { $0.providerRawValue == provider && $0.isEnabled })).first {
            do { try await freshRSSService.sync(account: account, in: context) } catch { refreshError = refreshError ?? error }
        }
        if let refreshError { presentedError = refreshError.localizedDescription }
    }
}
