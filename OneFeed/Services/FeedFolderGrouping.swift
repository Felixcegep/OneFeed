import Foundation

enum FeedFolderID: Hashable, Sendable {
    case named(String)
    case unfiled

    var title: String {
        switch self {
        case .named(let name): name
        case .unfiled: String(localized: "Unfiled")
        }
    }
}

struct FeedFolderGroup: Identifiable, Sendable {
    var id: FeedFolderID { folderID }
    let folderID: FeedFolderID
    let feeds: [Feed]

    var name: String { folderID.title }
}

struct FolderArticleGroup: Identifiable {
    var id: FeedFolderID { folderID }
    let folderID: FeedFolderID
    let articles: [Article]
    var name: String { folderID.title }
}

struct FolderSummary: Identifiable, Sendable {
    var id: FeedFolderID { folderID }
    let folderID: FeedFolderID
    let unreadCount: Int
    let feedCount: Int
    var name: String { folderID.title }
}

/// Folder membership for the Feed list. A refresh updates fetch time and does not change this token.
enum FeedMembershipEdge {
    static func token(of feeds: [Feed], includesEnabled: Bool, includesToday: Bool = false, includesTitle: Bool = false) -> Int {
        var token = feeds.count
        for feed in feeds {
            token = token &* 31 &+ feed.id.hashValue
            token = token &* 31 &+ feed.memberships.hashValue
            if includesEnabled {
                token = token &* 31 &+ (feed.isEnabled ? 1 : 0)
            }
            if includesToday {
                token = token &* 31 &+ (feed.includeInToday ? 1 : 0)
            }
            if includesTitle {
                token = token &* 31 &+ feed.title.hashValue
            }
        }
        return token
    }
}

/// Fields the folder list needs. Copied on the main thread so the count can run elsewhere.
struct FolderFeedSnap: Sendable {
    var id: UUID
    var memberships: [String]
}

struct FolderStorySnap: Sendable {
    var feedID: UUID?
    var publishedAt: Date
    var videoID: String?
    var url: URL?
    var guid: String
    var id: UUID
    var hasRemoteID: Bool
    var stateRaw: String
    var isRemoteStarred: Bool
}

/// Same folder counts as `FeedFolderGrouping.folderSummaries`, without the model objects.
nonisolated enum FolderDirectoryCount {
    /// A modest library can be counted on the open screen. A long one waits for the off-screen plan.
    static let synchronousCountLimit = 200

    static func countsOnTheOpenScreen(storyCount: Int) -> Bool {
        storyCount <= synchronousCountLimit
    }

    /// Copies open stories on a short-lived context. A long library uses this instead of walking the rows on screen.
    static func storySnaps(in container: ModelContainer) -> [FolderStorySnap] {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let queued = ArticleState.queued.rawValue
        let current = ArticleState.current.rawValue
        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { article in
                article.stateRawValue == queued || article.stateRawValue == current
            },
            sortBy: [SortDescriptor(\.publishedAt, order: .reverse)]
        )
        descriptor.propertiesToFetch = [
            \.id, \.publishedAt, \.videoID, \.url, \.guid, \.remoteID, \.stateRawValue, \.isRemoteStarred,
        ]
        descriptor.relationshipKeyPathsForPrefetching = [\.feed]
        let stories = (try? context.fetch(descriptor)) ?? []
        return stories.map { article in
            FolderStorySnap(
                feedID: article.feed?.id,
                publishedAt: article.publishedAt,
                videoID: article.videoID,
                url: article.url,
                guid: article.guid,
                id: article.id,
                hasRemoteID: article.remoteID != nil,
                stateRaw: article.stateRawValue,
                isRemoteStarred: article.isRemoteStarred
            )
        }
    }

    static func summaries(
        feeds: [FolderFeedSnap],
        stories: [FolderStorySnap],
        placements: [String: StoryPlacement],
        folderOrder: [String]
    ) -> [FolderSummary] {
        let open = collapsed(stories.sorted { $0.publishedAt > $1.publishedAt })
        return groups(from: feeds, folderOrder: folderOrder).map { group in
            let items = open.filter { story in
                guard let id = story.feedID else { return group.folderID == .unfiled }
                return group.feedIDs.contains(id)
            }
            let count = collapsedPrimaries(items, placements: placements).count
            return FolderSummary(folderID: group.folderID, unreadCount: count, feedCount: group.feedCount)
        }
    }

    /// Folder names in the same order as `summaries`, before unread counts exist. A zero count stays hidden.
    static func names(feeds: [FolderFeedSnap], folderOrder: [String]) -> [FolderSummary] {
        groups(from: feeds, folderOrder: folderOrder).map { group in
            FolderSummary(folderID: group.folderID, unreadCount: 0, feedCount: group.feedCount)
        }
    }

    private struct SnapGroup {
        var folderID: FeedFolderID
        var feedIDs: Set<UUID>
        var feedCount: Int
    }

    private static func groups(from feeds: [FolderFeedSnap], folderOrder: [String]) -> [SnapGroup] {
        var buckets: [FeedFolderID: [UUID]] = [:]
        for feed in feeds {
            if feed.memberships.isEmpty {
                buckets[.unfiled, default: []].append(feed.id)
                continue
            }
            for name in feed.memberships {
                buckets[.named(name), default: []].append(feed.id)
            }
        }
        let named = buckets
            .filter { $0.key != .unfiled }
            .sorted { precedes($0.key.title, $1.key.title, stored: folderOrder) }
            .map { SnapGroup(folderID: $0.key, feedIDs: Set($0.value), feedCount: $0.value.count) }
        if let unfiled = buckets[.unfiled], !unfiled.isEmpty {
            return named + [SnapGroup(folderID: .unfiled, feedIDs: Set(unfiled), feedCount: unfiled.count)]
        }
        return named
    }

    private static func precedes(_ lhs: String, _ rhs: String, stored: [String]) -> Bool {
        let li = stored.firstIndex { $0.caseInsensitiveCompare(lhs) == .orderedSame }
        let ri = stored.firstIndex { $0.caseInsensitiveCompare(rhs) == .orderedSame }
        switch (li, ri) {
        case let (l?, r?) where l != r: return l < r
        case (_?, nil): return true
        case (nil, _?): return false
        default: return FeedFolderGrouping.compareFolderNames(lhs, rhs)
        }
    }

    private static func collapsed(_ stories: [FolderStorySnap]) -> [FolderStorySnap] {
        var order: [String] = []
        var groups: [String: [FolderStorySnap]] = [:]
        for story in stories {
            let key = identityKey(story)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(story)
        }
        return order.map { key in
            let items = groups[key] ?? []
            return items.max(by: { score($0) < score($1) }) ?? items[0]
        }
    }

    private static func collapsedPrimaries(_ stories: [FolderStorySnap], placements: [String: StoryPlacement]) -> [FolderStorySnap] {
        let exact = ContentRelationship.exactDuplicate.rawValue
        let near = ContentRelationship.nearDuplicate.rawValue
        let sameStory = ContentRelationship.sameStory.rawValue
        let visible = stories.filter { story in
            let raw = placements[identityKey(story)]?.relationshipRaw
            return raw != exact && raw != near
        }
        var sameStoryClusters = Set<UUID>()
        for story in visible {
            guard let mark = placements[identityKey(story)],
                  mark.relationshipRaw == sameStory,
                  let clusterID = mark.storyClusterID else { continue }
            sameStoryClusters.insert(clusterID)
        }
        var emitted = Set<UUID>()
        var primaries: [FolderStorySnap] = []
        for story in visible {
            let key = identityKey(story)
            if let clusterID = placements[key]?.storyClusterID, sameStoryClusters.contains(clusterID) {
                guard emitted.insert(clusterID).inserted else { continue }
            }
            primaries.append(story)
        }
        return primaries
    }

    private static func identityKey(_ story: FolderStorySnap) -> String {
        if let videoID = story.videoID, !videoID.isEmpty { return "video:\(videoID)" }
        return ArticleIdentity.libraryKey(url: story.url, guid: story.guid, id: story.id)
    }

    private static func score(_ story: FolderStorySnap) -> Int {
        var value = 0
        if story.feedID != nil { value += 8 }
        if story.hasRemoteID { value += 4 }
        if story.stateRaw == "saved" || story.isRemoteStarred { value += 3 }
        if story.stateRaw == "current" { value += 2 }
        return value
    }
}

enum FeedFolderGrouping {
    static func openArticles(from articles: [Article]) -> [Article] {
        ArticleIdentity.collapsingDuplicates(
            articles
                .filter { $0.state == .queued || $0.state == .current }
                .sorted { $0.publishedAt > $1.publishedAt }
        )
    }

    static func todayArticles(from articles: [Article], calendar: Calendar = .current) -> [Article] {
        openArticles(from: articles).filter { calendar.isDateInToday($0.publishedAt) }
    }

    static func savedArticles(from articles: [Article]) -> [Article] {
        ArticleIdentity.collapsingDuplicates(
            articles
                .filter { $0.state == .saved }
                .sorted { ($0.completedAt ?? $0.publishedAt) > ($1.completedAt ?? $1.publishedAt) }
        )
    }

    static func folderSummaries(feeds: [Feed], articles: [Article]) -> [FolderSummary] {
        folderSummaries(feeds: feeds, articles: articles, placements: [:])
    }

    static func folderSummaries(
        feeds: [Feed],
        articles: [Article],
        placements: [String: StoryPlacement]
    ) -> [FolderSummary] {
        folderSummaries(feeds: feeds, openArticles: openArticles(from: articles), placements: placements)
    }

    static func folderSummaries(feeds: [Feed], openArticles open: [Article]) -> [FolderSummary] {
        folderSummaries(feeds: feeds, openArticles: open, placements: [:])
    }

    /// Counts the stories a folder list shows: exact and near copies drop out, and one same-story cluster counts once inside that folder.
    static func folderSummaries(
        feeds: [Feed],
        openArticles open: [Article],
        placements: [String: StoryPlacement]
    ) -> [FolderSummary] {
        groups(from: feeds).map { group in
            let stories = collapsedPrimaries(articles(in: group, from: open), placements: placements)
            return FolderSummary(folderID: group.folderID, unreadCount: stories.count, feedCount: group.feeds.count)
        }
    }

    static func collapsedPrimaries(_ articles: [Article], placements: [String: StoryPlacement]) -> [Article] {
        let exact = ContentRelationship.exactDuplicate.rawValue
        let near = ContentRelationship.nearDuplicate.rawValue
        let sameStory = ContentRelationship.sameStory.rawValue
        let visible = articles.filter { article in
            let raw = placements[ArticleIdentity.identityKey(for: article)]?.relationshipRaw
            return raw != exact && raw != near
        }
        var sameStoryClusters = Set<UUID>()
        for article in visible {
            guard let mark = placements[ArticleIdentity.identityKey(for: article)],
                  mark.relationshipRaw == sameStory,
                  let clusterID = mark.storyClusterID else { continue }
            sameStoryClusters.insert(clusterID)
        }
        var emitted = Set<UUID>()
        var primaries: [Article] = []
        primaries.reserveCapacity(visible.count)
        for article in visible {
            let key = ArticleIdentity.identityKey(for: article)
            if let clusterID = placements[key]?.storyClusterID, sameStoryClusters.contains(clusterID) {
                guard emitted.insert(clusterID).inserted else { continue }
            }
            primaries.append(article)
        }
        return primaries
    }

    private static func articles(in group: FeedFolderGroup, from open: [Article]) -> [Article] {
        let feedIDs = Set(group.feeds.map(\.id))
        return open.filter { article in
            guard let id = article.feed?.id else { return group.folderID == .unfiled }
            return feedIDs.contains(id)
        }
    }

    static func folderArticleGroups(from articles: [Article]) -> [FolderArticleGroup] {
        let open = openArticles(from: articles)
        var seen = Set<UUID>()
        var feeds: [Feed] = []
        for article in open {
            guard let feed = article.feed, seen.insert(feed.id).inserted else { continue }
            feeds.append(feed)
        }
        let feedGroups = groups(from: feeds)
        return feedGroups.compactMap { group in
            let feedIDs = Set(group.feeds.map(\.id))
            let items = open.filter { article in
                guard let id = article.feed?.id else { return group.folderID == .unfiled }
                return feedIDs.contains(id)
            }
            guard !items.isEmpty else { return nil }
            return FolderArticleGroup(folderID: group.folderID, articles: items)
        }
    }

    static func groups(from feeds: [Feed]) -> [FeedFolderGroup] {
        var buckets: [FeedFolderID: [Feed]] = [:]
        for feed in feeds {
            let names = feed.memberships
            if names.isEmpty {
                buckets[.unfiled, default: []].append(feed)
                continue
            }
            for name in names {
                buckets[.named(name), default: []].append(feed)
            }
        }
        let named = buckets
            .filter { $0.key != .unfiled }
            .sorted { lhs, rhs in
                folderPrecedes(lhs.key.title, rhs.key.title)
            }
            .map { FeedFolderGroup(folderID: $0.key, feeds: $0.value.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) }
        if let unfiled = buckets[.unfiled], !unfiled.isEmpty {
            return named + [FeedFolderGroup(folderID: .unfiled, feeds: unfiled.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })]
        }
        return named
    }

    /// Occupied folders plus remembered folders that do not yet contain a source.
    static func groupsIncludingKnownEmpty(from feeds: [Feed]) -> [FeedFolderGroup] {
        let occupied = groups(from: feeds)
        var named: [String: [Feed]] = [:]
        var unfiled: [Feed] = []
        for group in occupied {
            switch group.folderID {
            case .named(let name): named[name] = group.feeds
            case .unfiled: unfiled = group.feeds
            }
        }
        for name in FolderStore.knownNames() where named[name] == nil {
            if named.keys.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { continue }
            named[name] = []
        }
        let namedGroups = named.keys
            .sorted(by: folderPrecedes)
            .map { FeedFolderGroup(folderID: .named($0), feeds: named[$0] ?? []) }
        if unfiled.isEmpty { return namedGroups }
        return namedGroups + [FeedFolderGroup(folderID: .unfiled, feeds: unfiled)]
    }

    /// User order from Feed, then the seeded order, then alphabetical.
    nonisolated static func folderPrecedes(_ lhs: String, _ rhs: String) -> Bool {
        let stored = FolderStore.knownNames()
        let li = stored.firstIndex { $0.caseInsensitiveCompare(lhs) == .orderedSame }
        let ri = stored.firstIndex { $0.caseInsensitiveCompare(rhs) == .orderedSame }
        switch (li, ri) {
        case let (l?, r?) where l != r: return l < r
        case (_?, nil): return true
        case (nil, _?): return false
        default: return compareFolderNames(lhs, rhs)
        }
    }

    /// Seeded cadence/topic order first, then alphabetical extras.
    nonisolated static func compareFolderNames(_ lhs: String, _ rhs: String) -> Bool {
        let order = FeedSeedCatalog.folderOrder
        let li = order.firstIndex { $0.caseInsensitiveCompare(lhs) == .orderedSame }
        let ri = order.firstIndex { $0.caseInsensitiveCompare(rhs) == .orderedSame }
        switch (li, ri) {
        case let (l?, r?): return l < r
        case (_?, nil): return true
        case (nil, _?): return false
        default: return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }
}
