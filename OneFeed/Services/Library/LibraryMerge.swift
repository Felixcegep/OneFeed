import Foundation
import SwiftData

nonisolated enum LibraryMerge {
    static func snapshot(from context: ModelContext, now: Date = .now, extraTombstones: [LibraryTombstone] = []) throws -> LibraryDocument {
        let feeds = try context.fetch(FetchDescriptor<Feed>())
        let articles = try context.fetch(FetchDescriptor<Article>())
        let knowledgeNotes = try context.fetch(FetchDescriptor<KnowledgeNote>())
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
            knowledgeNotes: knowledgeNotes.map(record(from:)).sorted { $0.id.uuidString < $1.id.uuidString },
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
        let knowledgeNotes = mergedKnowledgeNotes(local: local.knowledgeNotes, remote: remote.knowledgeNotes)

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
            knowledgeNotes: knowledgeNotes,
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
                    try FeedRemovalService.remove(feed, in: context, save: false)
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

        let articles = try context.fetch(FetchDescriptor<Article>())
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

        // Notes are user-owned and sync independently from subscriptions and
        // reading-state preferences. Their copied provenance survives Article removal.
        let storedNotes = try context.fetch(FetchDescriptor<KnowledgeNote>())
        var notesByID = Dictionary(uniqueKeysWithValues: storedNotes.map { ($0.id, $0) })
        for record in document.knowledgeNotes {
            if let existing = notesByID[record.id] {
                let localRecord = Self.record(from: existing)
                let combinedHistory = mergedRevisionHistory(localRecord.revisionHistory, record.revisionHistory)
                if shouldPrefer(record, over: localRecord) {
                    var preferred = record
                    preferred.revisionHistory = combinedHistory
                    apply(preferred, to: existing)
                    changed += 1
                } else if combinedHistory != localRecord.revisionHistory {
                    existing.revisionHistory = combinedHistory
                    changed += 1
                }
            } else {
                let note = makeKnowledgeNote(from: record)
                context.insert(note)
                notesByID[note.id] = note
                changed += 1
            }
        }

        try applyCurrent(document, to: context)
        try context.save()
        return changed
    }

    static func applyCurrent(_ document: LibraryDocument, to context: ModelContext) throws {
        guard let key = document.currentArticleKey else { return }
        let articles = try context.fetch(FetchDescriptor<Article>())
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
            for item in deck.items.sorted(by: { $0.position < $1.position }) {
                guard let article = item.article, article.isStored else { continue }
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

    private static func record(from note: KnowledgeNote) -> LibraryKnowledgeNote {
        LibraryKnowledgeNote(
            id: note.id,
            title: note.title,
            explanation: note.explanation,
            formattedExplanation: note.formattedExplanation,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
            deletedAt: note.deletedAt,
            isDraft: note.isDraft,
            draftText: note.draftText,
            sourceArticleID: note.sourceArticleID,
            sourceTitle: note.sourceTitle,
            sourceURL: note.sourceURL?.absoluteString,
            sourceAuthor: note.sourceAuthor,
            sourcePublishedAt: note.sourcePublishedAt,
            sourceKind: note.sourceKind,
            sourceReferences: note.sourceReferences,
            revisionHistory: note.revisionHistory
        )
    }

    private static func mergedKnowledgeNotes(
        local: [LibraryKnowledgeNote],
        remote: [LibraryKnowledgeNote]
    ) -> [LibraryKnowledgeNote] {
        var byID: [UUID: LibraryKnowledgeNote] = [:]
        for note in local + remote {
            if let existing = byID[note.id] {
                var preferred = shouldPrefer(note, over: existing) ? note : existing
                preferred.revisionHistory = mergedRevisionHistory(existing.revisionHistory, note.revisionHistory)
                byID[note.id] = preferred
            } else {
                byID[note.id] = note
            }
        }
        return byID.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// Deletion is sticky because this release has no undelete operation. For
    /// live edits use updatedAt; ties use the canonical JSON representation so
    /// merging the same two snapshots in either order always picks the same row.
    private static func shouldPrefer(_ candidate: LibraryKnowledgeNote, over existing: LibraryKnowledgeNote) -> Bool {
        switch (candidate.deletedAt, existing.deletedAt) {
        case (.some, .none): return true
        case (.none, .some): return false
        case let (.some(candidateDeletion), .some(existingDeletion)):
            if candidateDeletion != existingDeletion { return candidateDeletion > existingDeletion }
        case (.none, .none):
            if candidate.updatedAt != existing.updatedAt { return candidate.updatedAt > existing.updatedAt }
        }
        return stableTieBreak(candidate) > stableTieBreak(existing)
    }

    private static func stableTieBreak(_ note: LibraryKnowledgeNote) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var payload = note
        payload.revisionHistory = nil
        guard let data = try? encoder.encode(payload) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func mergedRevisionHistory(_ local: Data?, _ remote: Data?) -> Data? {
        let decoder = JSONDecoder()
        let localRevisions = local.flatMap { try? decoder.decode([KnowledgeNoteRevision].self, from: $0) } ?? []
        let remoteRevisions = remote.flatMap { try? decoder.decode([KnowledgeNoteRevision].self, from: $0) } ?? []
        var byID: [UUID: KnowledgeNoteRevision] = [:]
        for revision in localRevisions + remoteRevisions {
            if let existing = byID[revision.id] {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let candidateData = try? encoder.encode(revision)
                let existingData = try? encoder.encode(existing)
                let candidateKey = candidateData.map { String(decoding: $0, as: UTF8.self) } ?? ""
                let existingKey = existingData.map { String(decoding: $0, as: UTF8.self) } ?? ""
                if candidateKey > existingKey { byID[revision.id] = revision }
            } else {
                byID[revision.id] = revision
            }
        }
        guard !byID.isEmpty else {
            if let local, let remote { return local.lexicographicallyPrecedes(remote) ? remote : local }
            return local ?? remote
        }
        let ordered = byID.values.sorted {
            if $0.savedAt != $1.savedAt { return $0.savedAt < $1.savedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(ordered)
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

    private static func apply(_ record: LibraryKnowledgeNote, to note: KnowledgeNote) {
        note.title = record.title
        note.explanation = record.explanation
        note.formattedExplanation = record.formattedExplanation
        note.createdAt = record.createdAt
        note.updatedAt = record.updatedAt
        note.deletedAt = record.deletedAt
        note.isDraft = record.isDraft
        note.draftText = record.draftText
        note.sourceArticleID = record.sourceArticleID
        note.sourceTitle = record.sourceTitle
        note.sourceURL = record.sourceURL.flatMap(URL.init(string:))
        note.sourceAuthor = record.sourceAuthor
        note.sourcePublishedAt = record.sourcePublishedAt
        note.sourceKind = record.sourceKind
        note.sourceReferences = record.sourceReferences
        note.revisionHistory = record.revisionHistory
    }

    private static func makeKnowledgeNote(from record: LibraryKnowledgeNote) -> KnowledgeNote {
        KnowledgeNote(
            id: record.id,
            title: record.title,
            explanation: record.explanation,
            formattedExplanation: record.formattedExplanation,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            deletedAt: record.deletedAt,
            isDraft: record.isDraft,
            draftText: record.draftText,
            revisionHistory: record.revisionHistory,
            sourceArticleID: record.sourceArticleID,
            sourceTitle: record.sourceTitle,
            sourceURL: record.sourceURL.flatMap(URL.init(string:)),
            sourceAuthor: record.sourceAuthor,
            sourcePublishedAt: record.sourcePublishedAt,
            sourceKind: record.sourceKind,
            sourceReferences: record.sourceReferences
        )
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
