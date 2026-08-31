import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class SavedViewModel {
    private var context: ModelContext?
    private let queue: ArticleQueueService
    private let freshRSSService: any FreshRSSSyncing
    private(set) var articles: [Article] = []
    var selectedArticle: Article?
    var presentedError: String?

    init() {
        queue = ArticleQueueService()
        freshRSSService = FreshRSSSyncService()
    }

    init(queue: ArticleQueueService, freshRSSService: any FreshRSSSyncing) {
        self.queue = queue
        self.freshRSSService = freshRSSService
    }

    func configure(with context: ModelContext) {
        self.context = context
        reload()
    }

    func reload() {
        guard let context else { return }
        let saved = ArticleState.saved.rawValue
        var descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.stateRawValue == saved || $0.isRemoteStarred })
        descriptor.sortBy = [SortDescriptor(\.completedAt, order: .reverse)]
        do { articles = try context.fetch(descriptor) }
        catch { presentedError = error.localizedDescription }
    }

    func restore(_ article: Article) {
        guard let context else { return }
        if article.remoteID != nil { freshRSSService.enqueueMutation(for: article, transition: .queued, in: context) }
        do { try queue.restoreSaved(article, in: context); reload() }
        catch { presentedError = error.localizedDescription }
    }

    func finishReading(_ article: Article, as state: ArticleState) {
        guard let context else { return }
        if state == .read {
            freshRSSService.enqueueMutation(for: article, transition: .read, in: context)
            do { _ = try queue.transition(article, to: .read, in: context) }
            catch { presentedError = error.localizedDescription }
        }
        selectedArticle = nil
        reload()
    }
}
