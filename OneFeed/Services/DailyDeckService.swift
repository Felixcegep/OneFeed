import Foundation
import SwiftData

@MainActor
struct DailyDeckService {
    func generateIfNeeded(in context: ModelContext, maxItems: Int = 10, persist: Bool = true) throws -> DailyDeck {
        try Self.generateIfNeeded(in: context, maxItems: maxItems, persist: persist)
    }

    nonisolated static func generateIfNeeded(in context: ModelContext, maxItems: Int = 10, persist: Bool = true) throws -> DailyDeck {
        if let existing = try todayDeck(in: context) {
            return existing
        }

        let deck = DailyDeck(dayStart: dayStart(for: .now), createdAt: .now)
        context.insert(deck)

        let selected = selectCandidates(from: try fetchCandidates(in: context), maxItems: maxItems, alreadySelected: [])
        for (index, article) in selected.enumerated() {
            let status: ArticleState = index == 0 ? .current : .queued
            let item = DailyDeckItem(position: index + 1, status: status, article: article, deck: deck)
            context.insert(item)
            article.state = status
            if index == 0 {
                article.firstDisplayedAt = .now
            }
        }

        if persist { try context.save() }
        WidgetSnapshotStore.write(article: selected.first)
        return try todayDeck(in: context) ?? deck
    }

    func todayDeck(in context: ModelContext) throws -> DailyDeck? {
        try Self.todayDeck(in: context)
    }

    nonisolated static func todayDeck(in context: ModelContext) throws -> DailyDeck? {
        let start = dayStart(for: .now)
        let descriptor = FetchDescriptor<DailyDeck>(predicate: #Predicate { $0.dayStart == start })
        return try context.fetch(descriptor).first
    }

    func currentItem(in context: ModelContext) throws -> DailyDeckItem? {
        guard let deck = try Self.todayDeck(in: context) else { return nil }
        let items = deck.items.sorted { $0.position < $1.position }
        if let current = items.first(where: { $0.status == .current && $0.article?.isStored == true }) {
            return current
        }
        var repaired = false
        if let orphan = items.first(where: { $0.status == .current }) {
            orphan.status = .skipped
            repaired = true
        }
        if let next = items.first(where: { $0.status == .queued && $0.article?.isStored == true }) {
            next.status = .current
            if let article = next.article {
                article.state = .current
                article.firstDisplayedAt = article.firstDisplayedAt ?? .now
                LibraryChange.note(article)
            }
            repaired = true
            if repaired { try context.save() }
            return next
        }
        if repaired { try context.save() }
        return nil
    }

    @discardableResult
    func advance(item: DailyDeckItem, to state: ArticleState, in context: ModelContext) throws -> DailyDeckItem? {
        precondition([.read, .skipped, .saved].contains(state), "Deck items can only advance to a terminal state")

        item.status = state
        if let article = item.article {
            article.state = state
            article.completedAt = .now
            if state == .saved { article.isRemoteStarred = true }
            LibraryChange.note(article)
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
                LibraryChange.note(article)
            }
        }

        try context.save()
        WidgetSnapshotStore.write(article: nextItem?.article)
        return nextItem
    }

    func remainingArticles(in context: ModelContext) throws -> [Article] {
        guard let deck = try Self.todayDeck(in: context) else { return [] }
        return deck.items
            .filter { $0.status == .current || $0.status == .queued }
            .sorted { $0.position < $1.position }
            .compactMap(\.article)
            .filter(\.isStored)
    }

    /// Turns sources on or off for Today and rebuilds the open part of today's stack.
    func setIncludedInToday(_ included: Bool, feeds: [Feed], in context: ModelContext) throws {
        try Self.setIncludedInToday(included, feeds: feeds, in: context)
    }

    /// Drops open stories whose sources are paused or left out, then fills the freed slots.
    func reconcileMembership(in context: ModelContext, maxItems: Int = 10) throws {
        try Self.reconcileMembership(in: context, maxItems: maxItems)
    }

    nonisolated static func setIncludedInToday(_ included: Bool, feeds: [Feed], in context: ModelContext) throws {
        let targets = feeds.filter { $0.includeInToday != included }
        guard !targets.isEmpty else { return }
        for feed in targets {
            feed.includeInToday = included
            feed.touchLibrary()
        }
        try reconcileMembership(in: context)
        Task { @MainActor in
            LibrarySyncService.shared.schedulePush()
        }
    }

    nonisolated static func reconcileMembership(in context: ModelContext, maxItems: Int = 10) throws {
        guard let deck = try todayDeck(in: context) else {
            try context.save()
            return
        }

        var droppedIDs = Set<UUID>()
        for item in deck.items where item.status == .current || item.status == .queued {
            guard !isEligibleForToday(item.article) else { continue }
            if let article = item.article, article.isStored, article.state == .current {
                article.state = .queued
                article.touchLibrary()
            }
            droppedIDs.insert(item.id)
            context.delete(item)
        }

        let live = deck.items
            .filter { !droppedIDs.contains($0.id) && !$0.isDeleted }
            .sorted { $0.position < $1.position }
        let open = live.filter { $0.status == .current || $0.status == .queued }
        if !open.contains(where: { $0.status == .current }), let next = open.first {
            next.status = .current
            if let article = next.article, article.isStored {
                article.state = .current
                article.firstDisplayedAt = article.firstDisplayedAt ?? .now
                article.touchLibrary()
            }
        }

        var appended: [DailyDeckItem] = []
        let room = max(0, maxItems - live.count)
        if room > 0 {
            let taken = Set(live.compactMap { $0.article?.id })
            let pool = try fetchCandidates(in: context).filter { !taken.contains($0.id) }
            let selected = selectCandidates(
                from: pool,
                maxItems: room,
                alreadySelected: live.compactMap(\.article)
            )
            var placedCurrent = live.contains { $0.status == .current }
            var position = live.map(\.position).max() ?? 0
            for article in selected {
                position += 1
                let status: ArticleState = placedCurrent ? .queued : .current
                placedCurrent = true
                let item = DailyDeckItem(position: position, status: status, article: article, deck: deck)
                context.insert(item)
                appended.append(item)
                if article.state != status {
                    article.state = status
                    article.touchLibrary()
                }
                if status == .current {
                    article.firstDisplayedAt = article.firstDisplayedAt ?? .now
                }
            }
        }

        let ordered = live + appended
        for (index, item) in ordered.enumerated() {
            item.position = index + 1
        }

        try context.save()
        let current = ordered.first { $0.status == .current }?.article
        WidgetSnapshotStore.write(article: current)
    }

    nonisolated private static func dayStart(for date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    nonisolated private static func isEligibleForToday(_ article: Article?) -> Bool {
        guard let article, article.isStored, let feed = article.feed else { return false }
        return feed.isEnabled && feed.includeInToday
    }

    nonisolated private static func fetchCandidates(in context: ModelContext) throws -> [Article] {
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
        descriptor.fetchLimit = 80
        let fetched = try context.fetch(descriptor)

        return fetched.filter { article in
            guard let feed = article.feed else { return false }
            return feed.isEnabled && feed.includeInToday
        }
    }

    nonisolated private static func selectCandidates(
        from candidates: [Article],
        maxItems: Int,
        alreadySelected: [Article]
    ) -> [Article] {
        var selected: [Article] = []
        var feedCounts: [UUID: Int] = [:]
        var lastTwoFeedIDs: [UUID] = []

        for article in alreadySelected {
            guard let feedID = article.feed?.id else { continue }
            feedCounts[feedID, default: 0] += 1
            lastTwoFeedIDs.append(feedID)
            if lastTwoFeedIDs.count > 2 {
                lastTwoFeedIDs.removeFirst()
            }
        }

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
