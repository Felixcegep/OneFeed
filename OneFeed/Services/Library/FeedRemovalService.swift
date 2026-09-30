import Foundation
import SwiftData

/// Removes a source and clears its daily deck links before the feed's cascade
/// invalidates the associated Article models.
nonisolated enum FeedRemovalService {
    nonisolated static func remove(_ feed: Feed, in context: ModelContext, save: Bool = true) throws {
        LibraryChange.noteRemovedFeed(feed)
        let feedID = feed.id
        let affectedDeckItems = try context.fetch(FetchDescriptor<DailyDeckItem>(
            predicate: #Predicate { $0.article?.feed?.id == feedID }
        ))
        for item in affectedDeckItems { context.delete(item) }
        context.delete(feed)

        if save { try context.save() }
    }

    /// Repairs stores created by older builds that deleted a source before
    /// unlinking its daily deck items. Do not inspect item.article here: that
    /// relationship may be the invalid persistent identifier being repaired.
    nonisolated static func repairLegacyDeckLinks(in context: ModelContext) throws {
        for item in try context.fetch(FetchDescriptor<DailyDeckItem>()) {
            context.delete(item)
        }
        for deck in try context.fetch(FetchDescriptor<DailyDeck>()) {
            context.delete(deck)
        }
        _ = try DailyDeckService.generateIfNeeded(in: context)
    }
}
