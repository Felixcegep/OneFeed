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
        descriptor.propertiesToFetch = [\.id, \.guid, \.stateRawValue]
        do { articles = ArticleIdentity.collapsingDuplicates(try context.fetch(descriptor)) }
        catch { presentedError = UserFacingFailure.message(for: error, fallback: "Couldn’t update Queue.") }
    }

    func openArticle(id: UUID) {
        guard let context else { return }
        var descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        selectedArticle = try? context.fetch(descriptor).first
    }

    func restore(_ article: Article) {
        guard let context, article.isStored else { return }
        if article.remoteID != nil { freshRSSService.enqueueMutation(for: article, transition: .queued, in: context) }
        do { try queue.restoreSaved(article, in: context) }
        catch { presentedError = UserFacingFailure.message(for: error, fallback: "Couldn’t update Queue.") }
    }

    @discardableResult
    func finishReading(_ article: Article, as state: ArticleState) -> Bool {
        guard let context else { return false }
        guard article.isStored else {
            selectedArticle = nil
            return true
        }
        if state == .read || state == .skipped {
            if state == .skipped {
                ReadingUndo.begin(article, in: context)
            }
            freshRSSService.enqueueMutation(for: article, transition: state, in: context)
            do {
                _ = try queue.transition(article, to: state, in: context)
                if state == .skipped {
                    ReadingUndo.commit(article, in: context)
                }
            } catch {
                presentedError = UserFacingFailure.message(for: error, fallback: "Couldn’t update Queue.")
                return false
            }
        }
        selectedArticle = nil
        return true
    }
}
