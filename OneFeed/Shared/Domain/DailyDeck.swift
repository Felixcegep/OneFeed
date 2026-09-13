import Foundation
import SwiftData

@Model
final class DailyDeck {
    @Attribute(.unique) var id: UUID
    /// Start of the local calendar day this deck belongs to.
    var dayStart: Date
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \DailyDeckItem.deck)
    var items: [DailyDeckItem] = []

    init(id: UUID = UUID(), dayStart: Date, createdAt: Date = .now) {
        self.id = id
        self.dayStart = dayStart
        self.createdAt = createdAt
    }
}
