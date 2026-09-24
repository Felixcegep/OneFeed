import Foundation
import SwiftData

nonisolated enum LibraryMerge {
    static func snapshot(from context: ModelContext, now: Date = .now, extraTombstones: [LibraryTombstone] = []) throws -> LibraryDocument {
        let feeds = try context.fetch(FetchDescriptor<Feed>())
        let articles = try context.fetch(ArticleListFetch.library())
        let feedRecords = feeds.map(record(from:))
        var articleRecords: [LibraryArticle] = []
        articleRecords.reserveCapacity(articles.count)
        var currentKey: String?
        var currentUpdatedAt: Date?
        for article in articles {
            guard let record = record(from: article) else { continue }
            articleRecords.append(record)
            if article.state == .current {
                if currentUpdatedAt == nil || record.updatedAt >= (currentUpdatedAt ?? .distantPast) {
                    currentKey = record.key
                    currentUpdatedAt = record.updatedAt
                }
            }
        }

        var tombstonesByURL: [String: Date] = [:]
        for tombstone in extraTombstones {
            tombstonesByURL[tombstone.feedURL] = max(tombstonesByURL[tombstone.feedURL] ?? .distantPast, tombstone.deletedAt)
        }
        let liveFeedKeys = Set(feedRecords.map(\.feedURL))
        let tombstones = tombstonesByURL
            .filter { !liveFeedKeys.contains($0.key) }
            .map { LibraryTombstone(feedURL: $0.key, deletedAt: $0.value) }
            .sorted { $0.feedURL < $1.feedURL }

        return LibraryDocument(
            schemaVersion: LibraryDocumentFormat.schemaVersion,
            updatedAt: now,
            folderNames: FolderStore.allNames(from: feeds),
            feeds: feedRecords.sorted { $0.feedURL < $1.feedURL },
            articles: articleRecords.sorted { $0.key < $1.key },
            tombstones: tombstones,
            currentArticleKey: currentKey,
            currentUpdatedAt: currentUpdatedAt
        )
    }

    static func merge(
        local: LibraryDocument,
        remote: LibraryDocument,
        now: Date = .now,
        options: LibraryMergeOptions = .all
    ) -> LibraryDocument {
        let tombstones = mergedTombstones(local: local.tombstones, remote: remote.tombstones)
        let feeds: [LibraryFeed]
        if options.syncFeeds {
            feeds = mergedFeeds(local: local.feeds, remote: remote.feeds, tombstones: tombstones)
        } else {
            feeds = local.feeds
        }
        let liveFeedKeys = Set(feeds.map(\.feedURL))
        let survivingTombstones = tombstones.filter { tombstone in
            guard let feed = feeds.first(where: { $0.feedURL == tombstone.feedURL }) else { return true }
            return feed.updatedAt <= tombstone.deletedAt
        }

        let articles = mergedArticles(
            local: local.articles,
            remote: remote.articles,
            liveFeedKeys: liveFeedKeys
        )

        let current: (key: String?, updatedAt: Date?)
        if (local.currentUpdatedAt ?? .distantPast) >= (remote.currentUpdatedAt ?? .distantPast) {
            current = (local.currentArticleKey, local.currentUpdatedAt)
        } else {
            current = (remote.currentArticleKey, remote.currentUpdatedAt)
        }

        let folders = FolderStore.normalize(local.folderNames + remote.folderNames)

        return LibraryDocument(
            schemaVersion: max(local.schemaVersion, remote.schemaVersion, LibraryDocumentFormat.schemaVersion),
            updatedAt: now,
            folderNames: folders,
            feeds: feeds.sorted { $0.feedURL < $1.feedURL },
            articles: articles.sorted { $0.key < $1.key },
            tombstones: survivingTombstones.filter { !liveFeedKeys.contains($0.feedURL) }.sorted { $0.feedURL < $1.feedURL },
            currentArticleKey: current.key,
            currentUpdatedAt: current.updatedAt
        )
    }

    @discardableResult
    static func apply(
        _ document: LibraryDocument,
        to context: ModelContext,
        options: LibraryMergeOptions = .all
    ) throws -> Int {
        var changed = 0
        let feeds = try context.fetch(FetchDescriptor<Feed>())
        var feedsByKey: [String: Feed] = [:]
        for feed in feeds {
            feedsByKey[ArticleIdentity.feedKey(feed.feedURL)] = feed
        }

        if options.syncFeeds {
            for tombstone in document.tombstones {
                guard let feed = feedsByKey[tombstone.feedURL] else { continue }
                if feed.libraryUpdatedAt <= tombstone.deletedAt {
                    context.delete(feed)
                    feedsByKey[tombstone.feedURL] = nil
                    changed += 1
                }
            }

            for record in document.feeds {
                if let existing = feedsByKey[record.feedURL] {
                    if record.updatedAt >= existing.libraryUpdatedAt {
                        apply(record, to: existing)
                        changed += 1
                    }
                } else {
                    let feed = makeFeed(from: record)
                    context.insert(feed)
                    feedsByKey[record.feedURL] = feed
                    changed += 1
                }
            }
        }

        FolderStore.remember(document.folderNames)

        let articles = try context.fetch(ArticleListFetch.library())
        var index = ArticleIdentityIndex(articles: articles)
        for record in document.articles {
            guard options.shouldApply(state: record.state) else { continue }
            guard let feed = feedsByKey[record.feedURL] ?? feed(matching: record.feedURL, in: feedsByKey) else { continue }
            let url = record.url.flatMap(URL.init(string:))
            if let existing = index.existing(url: url, guid: record.guid, feedID: feed.id) {
                if record.updatedAt >= existing.libraryUpdatedAt {
                    apply(record, to: existing)
                    changed += 1
                }
            } else {
                let article = makeArticle(from: record, feed: feed)
                context.insert(article)
                index.register(article)
                changed += 1
            }
        }

        try applyCurrent(document, to: context)
        try context.save()
        return changed
    }

    static func applyCurrent(_ document: LibraryDocument, to context: ModelContext) throws {
        guard let key = document.currentArticleKey else { return }
        var descriptor = FetchDescriptor<Article>()
        descriptor.propertiesToFetch = [
            \.id, \.guid, \.title, \.url, \.publishedAt, \.stateRawValue,
            \.completedAt, \.isRemoteStarred, \.libraryUpdatedAt, \.firstDisplayedAt,
            \.estimatedReadingMinutes, \.readingReactionRawValue, \.readingNote,
        ]
        descriptor.relationshipKeyPathsForPrefetching = [\.feed]
        let articles = try context.fetch(descriptor)
        guard let incoming = articles.first(where: { recordKey(for: $0) == key }) else { return }
        incoming.state = .current
        incoming.firstDisplayedAt = incoming.firstDisplayedAt ?? .now
        incoming.libraryUpdatedAt = max(incoming.libraryUpdatedAt, document.currentUpdatedAt ?? incoming.libraryUpdatedAt)
        for article in articles where article.id != incoming.id && article.state == .current {
            article.state = .queued
            article.firstDisplayedAt = nil
        }
        if let deck = try DailyDeckService.todayDeck(in: context) {
            var sawCurrent = false
            let articlesByID = Dictionary(uniqueKeysWithValues: articles.map { ($0.id, $0) })
            for item in deck.items.sorted(by: { $0.position < $1.position }) {
                guard let id = item.resolvedArticleID(), let article = articlesByID[id] else { continue }
                if article.id == incoming.id {
                    item.status = .current
                    sawCurrent = true
                } else if article.state == .queued {
                    item.status = .queued
                } else {
                    item.status = article.state
                }
            }
            if !sawCurrent {
                let nextPosition = (deck.items.map(\.position).max() ?? 0) + 1
                context.insert(DailyDeckItem(position: nextPosition, status: .current, article: incoming, deck: deck))
            }
        }
        WidgetSnapshotStore.write(article: incoming)
    }

    private static func record(from feed: Feed) -> LibraryFeed {
        LibraryFeed(
            feedURL: ArticleIdentity.feedKey(feed.feedURL),
            title: feed.title,
            websiteURL: feed.websiteURL?.absoluteString,
            folderName: feed.memberships.first,
            folderNames: feed.memberships,
            isEnabled: feed.isEnabled,
            contentKind: feed.contentKind,
            includeInToday: feed.includeInToday,
            includeVideos: feed.includeVideos,
            includeShorts: feed.includeShorts,
            minVideoSeconds: feed.minVideoSeconds,
            blockedWords: feed.blockedWords,
            updatedAt: feed.libraryUpdatedAt
        )
    }

    private static func record(from article: Article) -> LibraryArticle? {
        guard let url = article.url, let key = ArticleIdentity.normalizedURLString(url) else { return nil }
        guard let feedURL = article.feed.map({ ArticleIdentity.feedKey($0.feedURL) }) else { return nil }
        return LibraryArticle(
            key: "url:\(key)",
            feedURL: feedURL,
            guid: article.guid,
            title: article.title,
            url: key,
            state: article.state,
            completedAt: article.completedAt,
            isRemoteStarred: article.isRemoteStarred,
            updatedAt: article.libraryUpdatedAt,
            readingReactionRawValue: article.readingReactionRawValue,
            readingNote: article.readingNote
        )
    }

    private static func recordKey(for article: Article) -> String? {
        record(from: article)?.key
    }

    private static func mergedTombstones(local: [LibraryTombstone], remote: [LibraryTombstone]) -> [LibraryTombstone] {
        var dates: [String: Date] = [:]
        for tombstone in local + remote {
            dates[tombstone.feedURL] = max(dates[tombstone.feedURL] ?? .distantPast, tombstone.deletedAt)
        }
        return dates.map { LibraryTombstone(feedURL: $0.key, deletedAt: $0.value) }
    }

    private static func mergedFeeds(
        local: [LibraryFeed],
        remote: [LibraryFeed],
        tombstones: [LibraryTombstone]
    ) -> [LibraryFeed] {
        var byURL: [String: LibraryFeed] = [:]
        for feed in local { byURL[feed.feedURL] = feed }
        for feed in remote {
            if let existing = byURL[feed.feedURL] {
                if feed.updatedAt > existing.updatedAt { byURL[feed.feedURL] = feed }
            } else {
                byURL[feed.feedURL] = feed
            }
        }
        let tombstoneDates = Dictionary(uniqueKeysWithValues: tombstones.map { ($0.feedURL, $0.deletedAt) })
        for (url, deletedAt) in tombstoneDates {
            guard let feed = byURL[url] else { continue }
            if feed.updatedAt <= deletedAt {
                byURL[url] = nil
            }
        }
        return Array(byURL.values)
    }

    private static func mergedArticles(
        local: [LibraryArticle],
        remote: [LibraryArticle],
        liveFeedKeys: Set<String>
    ) -> [LibraryArticle] {
        var byKey: [String: LibraryArticle] = [:]
        for article in local { byKey[article.key] = article }
        for article in remote {
            if let existing = byKey[article.key] {
                if article.updatedAt > existing.updatedAt { byKey[article.key] = article }
            } else {
                byKey[article.key] = article
            }
        }
        guard !liveFeedKeys.isEmpty else { return Array(byKey.values) }
        return byKey.values.filter { liveFeedKeys.contains($0.feedURL) }.map { $0 }
    }

    private static func apply(_ record: LibraryFeed, to feed: Feed) {
        feed.title = record.title
        feed.websiteURL = record.websiteURL.flatMap(URL.init(string:))
        feed.setMemberships(record.resolvedFolderNames, touch: false)
        feed.isEnabled = record.isEnabled
        feed.contentKind = record.contentKind
        feed.includeInToday = record.includeInToday
        feed.includeVideos = record.includeVideos
        feed.includeShorts = record.includeShorts
        feed.minVideoSeconds = record.minVideoSeconds
        feed.blockedWords = record.blockedWords
        feed.libraryUpdatedAt = record.updatedAt
    }

    private static func apply(_ record: LibraryArticle, to article: Article) {
        article.title = record.title
        article.guid = record.guid
        if let url = record.url { article.url = URL(string: url) }
        article.state = record.state
        article.completedAt = record.completedAt
        article.isRemoteStarred = record.isRemoteStarred || record.state == .saved
        article.libraryUpdatedAt = record.updatedAt
        if record.state == .current {
            article.firstDisplayedAt = article.firstDisplayedAt ?? .now
        }
        article.readingReactionRawValue = ArticleReadingReaction.clampedRawValue(record.readingReactionRawValue)
        article.readingNote = record.readingNote
    }

    private static func makeFeed(from record: LibraryFeed) -> Feed {
        Feed(
            title: record.title,
            websiteURL: record.websiteURL.flatMap(URL.init(string:)),
            feedURL: URL(string: record.feedURL) ?? URL(string: "https://invalid.invalid")!,
            isEnabled: record.isEnabled,
            folderName: record.folderName,
            folderNames: record.resolvedFolderNames,
            contentKind: record.contentKind,
            includeInToday: record.includeInToday,
            includeVideos: record.includeVideos,
            includeShorts: record.includeShorts,
            minVideoSeconds: record.minVideoSeconds,
            blockedWords: record.blockedWords,
            libraryUpdatedAt: record.updatedAt
        )
    }

    private static func makeArticle(from record: LibraryArticle, feed: Feed) -> Article {
        let article = Article(
            guid: record.guid,
            title: record.title,
            url: record.url.flatMap(URL.init(string:)),
            publishedAt: record.completedAt ?? Date.distantPast,
            state: record.state,
            isRemoteStarred: record.isRemoteStarred || record.state == .saved,
            libraryUpdatedAt: record.updatedAt,
            readingReactionRawValue: ArticleReadingReaction.clampedRawValue(record.readingReactionRawValue),
            readingNote: record.readingNote,
            feed: feed
        )
        article.completedAt = record.completedAt
        if record.state == .current {
            article.firstDisplayedAt = .now
        }
        return article
    }

    private static func feed(matching key: String, in feeds: [String: Feed]) -> Feed? {
        feeds[key] ?? feeds.values.first { ArticleIdentity.feedKey($0.feedURL) == key }
    }
}
