import Foundation
import SwiftData

@Model
final class DailyDeckItem {
    @Attribute(.unique) var id: UUID
    /// 1-based position for display (e.g. "3 / 10").
    var position: Int
    var statusRawValue: String

    var article: Article?
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
        self.deck = deck
    }
}
