import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class CurrentViewModel {
    private var context: ModelContext?
    private let queue: ArticleQueueService
    private let feedService: any FeedRepository
    private let freshRSSService: any FreshRSSSyncing

    private(set) var currentArticle: Article?
    private(set) var isRefreshing = false
    var presentedError: String?

    init() {
        self.queue = ArticleQueueService()
        self.feedService = FeedService()
        self.freshRSSService = FreshRSSSyncService()
    }

    init(queue: ArticleQueueService, feedService: any FeedRepository, freshRSSService: any FreshRSSSyncing) {
        self.queue = queue
        self.feedService = feedService
        self.freshRSSService = freshRSSService
    }

    func configure(with context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context
        loadCurrent()
    }

    func loadCurrent() {
        guard let context else { return }
        do { currentArticle = try queue.ensureCurrent(in: context) }
        catch { presentedError = error.localizedDescription }
    }

    func transition(to state: ArticleState) {
        guard let context, let article = currentArticle else { return }
        freshRSSService.enqueueMutation(for: article, transition: state, in: context)
        do { currentArticle = try queue.transition(article, to: state, in: context) }
        catch { presentedError = error.localizedDescription }
    }

    func refresh() async {
        guard let context else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        var refreshError: Error?
        do { try await feedService.refreshAll(in: context) } catch { refreshError = error }
        let provider = SyncProvider.freshRSS.rawValue
        if let account = try? context.fetch(FetchDescriptor<SyncAccount>(predicate: #Predicate { $0.providerRawValue == provider && $0.isEnabled })).first {
            do { try await freshRSSService.sync(account: account, in: context) } catch { refreshError = refreshError ?? error }
        }
        do { currentArticle = try queue.ensureCurrent(in: context) }
        catch { refreshError = refreshError ?? error }
        if let refreshError { presentedError = refreshError.localizedDescription }
    }

    func clearError() { presentedError = nil }
}
