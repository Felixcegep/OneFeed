import Foundation
import SwiftData

/// Cross-feed identity for the same story. Local RSS and FreshRSS often
/// disagree on `guid` (entry id vs GReader item id), so URL is the real key.
nonisolated enum ArticleIdentity {
    private static let trackingQueryNames: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "fbclid", "gclid", "mc_cid", "mc_eid"
    ]

    static func normalizedURLString(_ url: URL?) -> String? {
        guard let url else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let host = components?.host {
            components?.host = host.lowercased()
        }
        components?.fragment = nil
        if var items = components?.queryItems, !items.isEmpty {
            items.removeAll { trackingQueryNames.contains($0.name.lowercased()) }
            components?.queryItems = items.isEmpty ? nil : items
        }
        if let path = components?.path, path.count > 1, path.hasSuffix("/") {
            components?.path = String(path.dropLast())
        }
        let value = components?.string ?? url.absoluteString
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func collapsingDuplicates(_ articles: [Article]) -> [Article] {
        var order: [String] = []
        var groups: [String: [Article]] = [:]
        groups.reserveCapacity(articles.count)
        for article in articles {
            let key = identityKey(for: article)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(article)
        }
        return order.map { preferred(in: groups[$0]!) }
    }

    @discardableResult
    static func mergeDuplicates(in context: ModelContext, persist: Bool = true) throws -> Int {
        let feedMerged = try mergeDuplicateFeeds(in: context)
        let articleMerged = try mergeDuplicateArticles(in: context)
        if persist, feedMerged + articleMerged > 0 {
            try context.save()
        }
        return feedMerged + articleMerged
    }

    static func preferred(in articles: [Article]) -> Article {
        articles.max(by: { score($0) < score($1) }) ?? articles[0]
    }

    /// Finds a saved story by URL without loading article bodies into the open screen.
    /// The scan uses a short-lived context. The story handed back already has the columns a row reads, so a later title read does not fault the page.
    static func storedArticle(matching url: URL, in context: ModelContext) -> Article? {
        guard let key = normalizedURLString(url) else { return nil }
        let lookup = ModelContext(context.container)
        lookup.autosaveEnabled = false
        var scan = FetchDescriptor<Article>()
        scan.propertiesToFetch = [\.id, \.url]
        let found = (try? lookup.fetch(scan)) ?? []
        guard let matchID = found.first(where: { normalizedURLString($0.url) == key })?.id else { return nil }
        var row = ArticleListFetch.rows(predicate: #Predicate { $0.id == matchID })
        row.fetchLimit = 1
        return try? context.fetch(row).first
    }

    static func identityKey(for article: Article) -> String {
        if let videoID = article.videoID, !videoID.isEmpty {
            return "video:\(videoID)"
        }
        return libraryKey(url: article.url, guid: article.guid, id: article.id)
    }

    static func libraryKey(url: URL?, guid: String, id: UUID) -> String {
        if let url = normalizedURLString(url) { return "url:\(url)" }
        return "id:\(id.uuidString)"
    }

    static func feedKey(_ url: URL) -> String {
        normalizedURLString(url) ?? url.absoluteString
    }

    /// Lists call this for every row. Do not touch `contentHTML`; that faults the stored body.
    private static func score(_ article: Article) -> Int {
        var value = 0
        if article.feed != nil { value += 8 }
        if article.remoteID != nil { value += 4 }
        if article.state == .saved || article.isRemoteStarred { value += 3 }
        if article.state == .current { value += 2 }
        return value
    }

    private static func mergeDuplicateFeeds(in context: ModelContext) throws -> Int {
        let feeds = try context.fetch(FetchDescriptor<Feed>())
        var groups: [String: [Feed]] = [:]
        for feed in feeds {
            let key = normalizedURLString(feed.feedURL) ?? feed.feedURL.absoluteString
            groups[key, default: []].append(feed)
        }
        var removed = 0
        for group in groups.values where group.count > 1 {
            let keeper = preferredFeed(in: group)
            for duplicate in group where duplicate.id != keeper.id {
                let articles = Array(duplicate.articles)
                for article in articles { article.feed = keeper }
                if keeper.remoteID == nil { keeper.remoteID = duplicate.remoteID }
                let combined = FeedMembership.normalize(keeper.memberships + duplicate.memberships)
                if combined != keeper.memberships {
                    keeper.setMemberships(combined, touch: false)
                }
                if keeper.websiteURL == nil { keeper.websiteURL = duplicate.websiteURL }
                context.delete(duplicate)
                removed += 1
            }
        }
        return removed
    }

    private static func mergeDuplicateArticles(in context: ModelContext) throws -> Int {
        let scan = ModelContext(context.container)
        scan.autosaveEnabled = false
        var descriptor = FetchDescriptor<Article>()
        descriptor.propertiesToFetch = [\.id, \.guid, \.url, \.videoID, \.stateRawValue, \.remoteID, \.isRemoteStarred]
        descriptor.relationshipKeyPathsForPrefetching = [\.feed]
        let articles = try scan.fetch(descriptor)
        var videoGroups: [String: [Article]] = [:]
        var urlGroups: [String: [Article]] = [:]
        for article in articles {
            if let videoID = article.videoID, !videoID.isEmpty {
                videoGroups[videoID, default: []].append(article)
            } else if let url = normalizedURLString(article.url) {
                urlGroups[url, default: []].append(article)
            }
        }
        var keeperIDs: [UUID: UUID] = [:]
        var removedIDs = Set<UUID>()
        func plan(_ groups: [String: [Article]]) {
            for group in groups.values where group.count > 1 {
                let alive = group.filter { !removedIDs.contains($0.id) }
                guard alive.count > 1 else { continue }
                let keeper = preferred(in: alive)
                for duplicate in alive where duplicate.id != keeper.id {
                    keeperIDs[duplicate.id] = keeper.id
                    removedIDs.insert(duplicate.id)
                }
            }
        }
        plan(videoGroups)
        plan(urlGroups)
        guard !keeperIDs.isEmpty else { return 0 }

        let neededIDs = Array(Set(keeperIDs.keys).union(keeperIDs.values))
        let rows = try context.fetch(ArticleListFetch.rows(predicate: #Predicate { neededIDs.contains($0.id) }))
        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let deckItems = (try? context.fetch(FetchDescriptor<DailyDeckItem>())) ?? []
        var removed = 0
        for (duplicateID, keeperID) in keeperIDs {
            guard let duplicate = byID[duplicateID], let keeper = byID[keeperID] else { continue }
            absorb(duplicate, into: keeper)
            for item in deckItems where item.resolvedArticleID() == duplicate.id {
                item.article = keeper
                item.linkedArticleID = keeper.id
            }
            context.delete(duplicate)
            removed += 1
        }
        return removed
    }

    /// Reads of `contentHTML` on the articles being merged. A saved body is measured
    /// on a short-lived context and does not increment this.
    static var liveHTMLReads = 0

    private static func absorb(_ duplicate: Article, into keeper: Article) {
        let keeperCount = htmlCount(keeper)
        let duplicateCount = htmlCount(duplicate)
        if keeper.feed == nil { keeper.feed = duplicate.feed }
        if keeper.remoteID == nil { keeper.remoteID = duplicate.remoteID }
        if keeper.url == nil { keeper.url = duplicate.url }
        if keeperCount < duplicateCount {
            keeper.contentHTML = html(duplicate)
            keeper.refreshEstimatedReadingMinutes()
        }
        if (keeper.summary ?? "").count < (duplicate.summary ?? "").count {
            keeper.summary = duplicate.summary
        }
        if keeper.imageURL == nil { keeper.imageURL = duplicate.imageURL }
        if duplicate.isRemoteStarred { keeper.isRemoteStarred = true }
        if duplicate.state == .saved, keeper.state != .read, keeper.state != .skipped {
            keeper.state = .saved
        }
        if duplicate.state == .current, keeper.state == .queued {
            keeper.state = .current
            keeper.firstDisplayedAt = duplicate.firstDisplayedAt ?? keeper.firstDisplayedAt
        }
    }

    /// An unsaved insert or edit still holds its body in memory. A saved article is counted from the store.
    private static func htmlCount(_ article: Article) -> Int {
        if usesLiveHTML(article) {
            liveHTMLReads += 1
            return article.contentHTML?.count ?? 0
        }
        guard let container = article.modelContext?.container else {
            liveHTMLReads += 1
            return article.contentHTML?.count ?? 0
        }
        return storedHTMLCount(id: article.id, container: container)
    }

    private static func html(_ article: Article) -> String {
        if usesLiveHTML(article) {
            liveHTMLReads += 1
            return article.contentHTML ?? ""
        }
        guard let container = article.modelContext?.container else {
            liveHTMLReads += 1
            return article.contentHTML ?? ""
        }
        return storedHTML(id: article.id, container: container) ?? ""
    }

    private static func usesLiveHTML(_ article: Article) -> Bool {
        guard let context = article.modelContext else { return true }
        let id = article.persistentModelID
        if context.insertedModelsArray.contains(where: { $0.persistentModelID == id }) { return true }
        if context.changedModelsArray.contains(where: { $0.persistentModelID == id }) { return true }
        return false
    }

    private static func storedHTMLCount(id: UUID, container: ModelContainer) -> Int {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let matchID = id
        var descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.id == matchID })
        descriptor.fetchLimit = 1
        guard let stored = try? context.fetch(descriptor).first else { return 0 }
        return stored.contentHTML?.count ?? 0
    }

    private static func storedHTML(id: UUID, container: ModelContainer) -> String? {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let matchID = id
        var descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.id == matchID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first?.contentHTML
    }

    private static func preferredFeed(in feeds: [Feed]) -> Feed {
        feeds.max { lhs, rhs in
            let left = (lhs.remoteID != nil ? 2 : 0) + lhs.articles.count
            let right = (rhs.remoteID != nil ? 2 : 0) + rhs.articles.count
            return left < right
        } ?? feeds[0]
    }
}

nonisolated struct ArticleIdentityIndex {
    private var byNormalizedURL: [String: Article] = [:]
    private var byFeedAndGUID: [String: Article] = [:]
    private var byRemoteID: [String: Article] = [:]
    private var byVideoID: [String: Article] = [:]

    init(articles: [Article] = []) {
        for article in articles { register(article) }
    }

    mutating func register(_ article: Article) {
        if let key = ArticleIdentity.normalizedURLString(article.url) {
            if let existing = byNormalizedURL[key] {
                byNormalizedURL[key] = ArticleIdentity.preferred(in: [existing, article])
            } else {
                byNormalizedURL[key] = article
            }
        }
        byFeedAndGUID[guidKey(feedID: article.feed?.id, guid: article.guid)] = article
        if let remoteID = article.remoteID {
            if let existing = byRemoteID[remoteID] {
                byRemoteID[remoteID] = ArticleIdentity.preferred(in: [existing, article])
            } else {
                byRemoteID[remoteID] = article
            }
        }
        if let videoID = article.videoID, !videoID.isEmpty {
            if let existing = byVideoID[videoID] {
                byVideoID[videoID] = ArticleIdentity.preferred(in: [existing, article])
            } else {
                byVideoID[videoID] = article
            }
        }
    }

    func existing(
        url: URL?,
        guid: String,
        feedID: UUID,
        remoteID: String? = nil,
        videoID: String? = nil
    ) -> Article? {
        if let remoteID, let found = byRemoteID[remoteID] {
            return found
        }
        if let videoID, !videoID.isEmpty, let found = byVideoID[videoID] {
            return found
        }
        if let key = ArticleIdentity.normalizedURLString(url), let found = byNormalizedURL[key] {
            return found
        }
        return byFeedAndGUID[guidKey(feedID: feedID, guid: guid)]
    }

    private func guidKey(feedID: UUID?, guid: String) -> String {
        "\(feedID?.uuidString ?? "none")|\(guid)"
    }
}

/// Order-sensitive identity for a list cache. A middle replacement changes the token.
nonisolated enum ListIdentity {
    static func token(ids: some Sequence<UUID>) -> Int {
        var count = 0
        var mixed = 0
        for id in ids {
            count += 1
            mixed = mixed &* 31 &+ id.hashValue
        }
        return count &* 31 &+ mixed
    }
}
