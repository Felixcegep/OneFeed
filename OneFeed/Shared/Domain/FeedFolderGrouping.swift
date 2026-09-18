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

struct FolderSummary: Identifiable {
    var id: FeedFolderID { folderID }
    let folderID: FeedFolderID
    let unreadCount: Int
    let feedCount: Int
    var name: String { folderID.title }
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
        folderSummaries(feeds: feeds, openArticles: openArticles(from: articles))
    }

    static func folderSummaries(feeds: [Feed], openArticles open: [Article]) -> [FolderSummary] {
        var counts: [UUID: Int] = [:]
        var unfiledOrphans = 0
        counts.reserveCapacity(open.count)
        for article in open {
            if let id = article.feed?.id {
                counts[id, default: 0] += 1
            } else {
                unfiledOrphans += 1
            }
        }
        return groups(from: feeds).map { group in
            let fromFeeds = group.feeds.reduce(0) { $0 + (counts[$1.id] ?? 0) }
            let unreadCount = group.folderID == .unfiled ? fromFeeds + unfiledOrphans : fromFeeds
            return FolderSummary(folderID: group.folderID, unreadCount: unreadCount, feedCount: group.feeds.count)
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
            let name = feed.folderName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let id: FeedFolderID = name.isEmpty ? .unfiled : .named(name)
            buckets[id, default: []].append(feed)
        }
        let named = buckets
            .filter { $0.key != .unfiled }
            .sorted { lhs, rhs in
                compareFolderNames(lhs.key.title, rhs.key.title)
            }
            .map { FeedFolderGroup(folderID: $0.key, feeds: $0.value.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) }
        if let unfiled = buckets[.unfiled], !unfiled.isEmpty {
            return named + [FeedFolderGroup(folderID: .unfiled, feeds: unfiled.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })]
        }
        return named
    }

    /// Seeded cadence/topic order first, then alphabetical extras.
    static func compareFolderNames(_ lhs: String, _ rhs: String) -> Bool {
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
