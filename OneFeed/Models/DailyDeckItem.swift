import Foundation
import SwiftData

@Model
final class DailyDeckItem {
    @Attribute(.unique) var id: UUID
    /// 1-based position for display (e.g. "3 / 10").
    var position: Int
    var statusRawValue: String

    var article: Article?
    /// Stored article id so a refresh can recognize the row without opening the page.
    var linkedArticleID: UUID?
    var deck: DailyDeck?

    var status: ArticleState {
        get { ArticleState(rawValue: statusRawValue) ?? .queued }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        position: Int,
        status: ArticleState = .queued,
        article: Article? = nil,
        deck: DailyDeck? = nil
    ) {
        self.id = id
        self.position = position
        self.statusRawValue = status.rawValue
        self.article = article
        self.linkedArticleID = article?.id
        self.deck = deck
    }

    /// The article id already stored on the row. An older row remembers it on first lookup.
    func resolvedArticleID() -> UUID? {
        if let linkedArticleID { return linkedArticleID }
        guard let id = article?.id else { return nil }
        linkedArticleID = id
        return id
    }

    /// The linked story is still in the store. Uses the stored id, so the page stays on disk.
    func articleExists(in context: ModelContext) -> Bool {
        guard let id = resolvedArticleID() else { return false }
        let matchID = id
        var descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.id == matchID })
        descriptor.fetchLimit = 1
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }
}
