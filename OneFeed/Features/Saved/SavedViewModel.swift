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
    }

    func reload() {
        guard let context else { return }
        let saved = ArticleState.saved.rawValue
        var descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.stateRawValue == saved })
        descriptor.sortBy = [SortDescriptor(\.completedAt, order: .reverse)]
        do { articles = ArticleIdentity.collapsingDuplicates(try context.fetch(descriptor)) }
        catch { presentedError = error.localizedDescription }
    }

    func restore(_ article: Article) {
        guard let context, article.isStored else { return }
        if article.remoteID != nil { freshRSSService.enqueueMutation(for: article, transition: .queued, in: context) }
        do { try queue.restoreSaved(article, in: context); reload() }
        catch { presentedError = error.localizedDescription }
    }

    func finishReading(_ article: Article, as state: ArticleState) {
        guard let context else { return }
        selectedArticle = nil
        guard article.isStored else {
            reload()
            return
        }
        if state == .read || state == .skipped {
            freshRSSService.enqueueMutation(for: article, transition: state, in: context)
            do { _ = try queue.transition(article, to: state, in: context) }
            catch { presentedError = error.localizedDescription }
        }
        selectedArticle = nil
        reload()
    }
}
