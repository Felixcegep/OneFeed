import Foundation
import SwiftData

@MainActor
struct DailyDeckService {
    func generateIfNeeded(in context: ModelContext, maxItems: Int = 10) throws -> DailyDeck {
        if let existing = try todayDeck(in: context) {
            return existing
        }

        let deck = DailyDeck(dayStart: Self.dayStart(for: .now), createdAt: .now)
        context.insert(deck)

        let selected = Self.selectCandidates(from: try Self.fetchCandidates(in: context), maxItems: maxItems)
        for (index, article) in selected.enumerated() {
            let status: ArticleState = index == 0 ? .current : .queued
            let item = DailyDeckItem(position: index + 1, status: status, article: article, deck: deck)
            context.insert(item)
            article.state = status
            if index == 0 {
                article.firstDisplayedAt = .now
            }
        }

        try context.save()
        WidgetSnapshotStore.write(article: selected.first)
        return try todayDeck(in: context) ?? deck
    }

    func todayDeck(in context: ModelContext) throws -> DailyDeck? {
        let start = Self.dayStart(for: .now)
        let descriptor = FetchDescriptor<DailyDeck>(predicate: #Predicate { $0.dayStart == start })
        return try context.fetch(descriptor).first
    }

    func currentItem(in context: ModelContext) throws -> DailyDeckItem? {
        guard let deck = try todayDeck(in: context) else { return nil }
        let currentValue = ArticleState.current.rawValue
        return deck.items.first { $0.statusRawValue == currentValue }
    }

    @discardableResult
    func advance(item: DailyDeckItem, to state: ArticleState, in context: ModelContext) throws -> DailyDeckItem? {
        precondition([.read, .skipped, .saved].contains(state), "Deck items can only advance to a terminal state")

        item.status = state
        if let article = item.article {
            article.state = state
            article.completedAt = .now
            if state == .saved { article.isRemoteStarred = true }
            if state == .read { article.isRemoteStarred = false }
        }

        let nextItem = item.deck?.items
            .filter { $0.status == .queued }
            .sorted { $0.position < $1.position }
            .first

        if let nextItem {
            nextItem.status = .current
            if let article = nextItem.article {
                article.state = .current
                article.firstDisplayedAt = .now
            }
        }

        try context.save()
        WidgetSnapshotStore.write(article: nextItem?.article)
        return nextItem
    }

    private static func dayStart(for date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private static func fetchCandidates(in context: ModelContext) throws -> [Article] {
        let cutoff = Date().addingTimeInterval(-86_400)
        let skipped = ArticleState.skipped.rawValue
        let read = ArticleState.read.rawValue
        let queued = ArticleState.queued.rawValue

        var descriptor = FetchDescriptor<Article>(predicate: #Predicate { article in
            article.publishedAt >= cutoff &&
            (article.stateRawValue == queued ||
             (article.stateRawValue != skipped && article.stateRawValue != read))
        })
        descriptor.sortBy = [SortDescriptor(\.publishedAt, order: .reverse)]
        let fetched = try context.fetch(descriptor)

        return fetched.filter { article in
            guard let feed = article.feed else { return false }
            return feed.isEnabled && feed.includeInToday
        }
    }

    private static func selectCandidates(from candidates: [Article], maxItems: Int) -> [Article] {
        var selected: [Article] = []
        var feedCounts: [UUID: Int] = [:]
        var lastTwoFeedIDs: [UUID] = []

        for article in candidates {
            guard selected.count < maxItems, let feedID = article.feed?.id else { continue }
            guard (feedCounts[feedID] ?? 0) < 2 else { continue }
            if lastTwoFeedIDs.count == 2, lastTwoFeedIDs[0] == feedID, lastTwoFeedIDs[1] == feedID {
                continue
            }

            selected.append(article)
            feedCounts[feedID, default: 0] += 1
            lastTwoFeedIDs.append(feedID)
            if lastTwoFeedIDs.count > 2 {
                lastTwoFeedIDs.removeFirst()
            }
        }

        return selected
    }
}
