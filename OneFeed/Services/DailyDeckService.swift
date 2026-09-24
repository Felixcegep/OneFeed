import Foundation
import SwiftData

@MainActor
struct DailyDeckService {
    func generateIfNeeded(in context: ModelContext, maxItems: Int = 10, persist: Bool = true) throws -> DailyDeck {
        try Self.generateIfNeeded(in: context, maxItems: maxItems, persist: persist)
    }

    nonisolated static func generateIfNeeded(in context: ModelContext, maxItems: Int = 10, persist: Bool = true) throws -> DailyDeck {
        if let existing = try todayDeck(in: context) {
            try topUpCaughtUpDeck(existing, in: context, maxItems: maxItems, persist: persist)
            return try todayDeck(in: context) ?? existing
        }

        let deck = DailyDeck(dayStart: dayStart(for: .now), createdAt: .now)
        context.insert(deck)

        let placements = try storyPlacements(in: context)
        let selected = selectCandidates(
            from: try fetchCandidates(in: context),
            maxItems: maxItems,
            alreadySelected: [],
            placements: placements
        )
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
        if let current = items.first(where: { $0.status == .current && $0.articleExists(in: context) }) {
            return current
        }
        var repaired = false
        if let orphan = items.first(where: { $0.status == .current }) {
            orphan.status = .skipped
            repaired = true
        }
        if let next = items.first(where: { $0.status == .queued && $0.articleExists(in: context) }) {
            next.status = .current
            if let id = next.resolvedArticleID(), let article = Self.lightweightArticle(id: id, in: context) {
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
            .compactMap { item in
                guard let id = item.resolvedArticleID() else { return nil }
                return Self.lightweightArticle(id: id, in: context)
            }
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
        try storeIncludedInToday(included, feeds: feeds, in: context)
        try reconcileMembership(in: context)
    }

    /// Saves the switches and leaves today's stack alone. The filter sheet reconciles once when it closes.
    nonisolated static func storeIncludedInToday(_ included: Bool, feeds: [Feed], in context: ModelContext) throws {
        let targets = feeds.filter { $0.includeInToday != included }
        guard !targets.isEmpty else { return }
        for feed in targets {
            feed.includeInToday = included
            feed.touchLibrary()
        }
        try context.save()
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
            let linked = item.resolvedArticleID().flatMap { lightweightArticle(id: $0, in: context) }
            guard !isEligibleForToday(linked) else { continue }
            if let article = linked, article.state == .current {
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
            if let id = next.resolvedArticleID(), let article = lightweightArticle(id: id, in: context) {
                article.state = .current
                article.firstDisplayedAt = article.firstDisplayedAt ?? .now
                article.touchLibrary()
            }
        }

        var appended: [DailyDeckItem] = []
        let room = max(0, maxItems - live.count)
        if room > 0 {
            let taken = Set(live.compactMap { $0.resolvedArticleID() })
            let placements = try storyPlacements(in: context)
            let pool = try fetchCandidates(in: context).filter { !taken.contains($0.id) }
            let selected = selectCandidates(
                from: pool,
                maxItems: room,
                alreadySelected: live.compactMap { item in
                    item.resolvedArticleID().flatMap { lightweightArticle(id: $0, in: context) }
                },
                placements: placements
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

    /// When today's stack is finished, refresh can fill another batch. An open story stays put.
    nonisolated private static func topUpCaughtUpDeck(
        _ deck: DailyDeck,
        in context: ModelContext,
        maxItems: Int,
        persist: Bool
    ) throws {
        let hasOpenStory = deck.items.contains {
            ($0.status == .current || $0.status == .queued) && $0.articleExists(in: context)
        }
        guard !hasOpenStory else { return }

        let taken = Set(deck.items.compactMap { $0.resolvedArticleID() })
        let placements = try storyPlacements(in: context)
        let pool = try fetchCandidates(in: context).filter { !taken.contains($0.id) }
        let selected = selectCandidates(
            from: pool,
            maxItems: maxItems,
            alreadySelected: deck.items.compactMap { item in
                item.resolvedArticleID().flatMap { lightweightArticle(id: $0, in: context) }
            },
            placements: placements
        )
        guard !selected.isEmpty else { return }

        var position = deck.items.map(\.position).max() ?? 0
        var placedCurrent = false
        for article in selected {
            position += 1
            let status: ArticleState = placedCurrent ? .queued : .current
            placedCurrent = true
            let item = DailyDeckItem(position: position, status: status, article: article, deck: deck)
            context.insert(item)
            if article.state != status {
                article.state = status
                article.touchLibrary()
            }
            if status == .current {
                article.firstDisplayedAt = article.firstDisplayedAt ?? .now
            }
        }

        if persist { try context.save() }
        WidgetSnapshotStore.write(article: selected.first)
    }

    /// Identity and state for a deck row. The stored page stays on disk.
    nonisolated static func lightweightArticle(id: UUID, in context: ModelContext) -> Article? {
        let matchID = id
        var descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.id == matchID })
        descriptor.fetchLimit = 1
        descriptor.propertiesToFetch = [
            \.id, \.guid, \.url, \.title, \.publishedAt, \.stateRawValue, \.videoID,
            \.firstDisplayedAt, \.completedAt, \.libraryUpdatedAt, \.estimatedReadingMinutes,
            \.contentKind, \.isRemoteStarred,
        ]
        descriptor.relationshipKeyPathsForPrefetching = [\.feed]
        return try? context.fetch(descriptor).first
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
        // The body stays on disk. Choosing today's stories only needs identity, state, and the source.
        descriptor.propertiesToFetch = [
            \.id, \.guid, \.url, \.title, \.publishedAt, \.stateRawValue, \.videoID,
            \.firstDisplayedAt, \.libraryUpdatedAt, \.estimatedReadingMinutes, \.contentKind,
        ]
        descriptor.relationshipKeyPathsForPrefetching = [\.feed]
        let fetched = try context.fetch(descriptor)

        return fetched.filter { article in
            guard let feed = article.feed else { return false }
            return feed.isEnabled && feed.includeInToday
        }
    }

    static func loadStoryPlacements(in context: ModelContext) -> [String: StoryPlacement] {
        (try? storyPlacements(in: context)) ?? [:]
    }

    /// Reads cluster captions off the main actor so opening Feed does not stall the list.
    static func loadStoryPlacements(from container: ModelContainer) async -> [String: StoryPlacement] {
        await Task.detached(priority: .utility) {
            loadStoryPlacements(in: ModelContext(container))
        }.value
    }

    nonisolated private static func storyPlacements(in context: ModelContext) throws -> [String: StoryPlacement] {
        var descriptor = FetchDescriptor<ContentMemory>()
        descriptor.propertiesToFetch = [\.identityKey, \.relationshipRaw, \.storyClusterID, \.matchedConsumedAt]
        let memories = try context.fetch(descriptor)
        var lookup: [String: StoryPlacement] = [:]
        lookup.reserveCapacity(memories.count)
        for memory in memories {
            lookup[memory.identityKey] = StoryPlacement(
                relationshipRaw: memory.relationshipRaw,
                storyClusterID: memory.storyClusterID,
                matchedConsumedAt: memory.matchedConsumedAt
            )
        }
        return lookup
    }

    nonisolated private static func selectCandidates(
        from candidates: [Article],
        maxItems: Int,
        alreadySelected: [Article],
        placements: [String: StoryPlacement] = [:]
    ) -> [Article] {
        let collapsed: Set<String> = [
            ContentRelationship.exactDuplicate.rawValue,
            ContentRelationship.nearDuplicate.rawValue,
        ]
        let eligible = candidates.filter { article in
            guard let placement = placements[ArticleIdentity.identityKey(for: article)] else { return true }
            return !collapsed.contains(placement.relationshipRaw)
        }

        var selected: [Article] = []
        var feedCounts: [UUID: Int] = [:]
        var lastTwoFeedIDs: [UUID] = []
        var usedClusters = Set<UUID>()

        func noteFeed(_ article: Article) {
            guard let feedID = article.feed?.id else { return }
            feedCounts[feedID, default: 0] += 1
            lastTwoFeedIDs.append(feedID)
            if lastTwoFeedIDs.count > 2 {
                lastTwoFeedIDs.removeFirst()
            }
        }

        func noteCluster(_ article: Article) {
            guard let clusterID = placements[ArticleIdentity.identityKey(for: article)]?.storyClusterID else { return }
            usedClusters.insert(clusterID)
        }

        for article in alreadySelected {
            noteFeed(article)
            noteCluster(article)
        }

        for article in eligible {
            guard selected.count < maxItems, let feedID = article.feed?.id else { continue }
            guard (feedCounts[feedID] ?? 0) < 2 else { continue }
            if lastTwoFeedIDs.count == 2, lastTwoFeedIDs[0] == feedID, lastTwoFeedIDs[1] == feedID {
                continue
            }
            if let clusterID = placements[ArticleIdentity.identityKey(for: article)]?.storyClusterID,
               usedClusters.contains(clusterID) {
                continue
            }

            selected.append(article)
            noteFeed(article)
            noteCluster(article)
        }

        return selected
    }
}

nonisolated struct StoryPlacement: Equatable, Sendable {
    var relationshipRaw: String
    var storyClusterID: UUID?
    var matchedConsumedAt: Date? = nil
}
