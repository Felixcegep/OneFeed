import Foundation
import SwiftData

/// A Not interested mark stays only when the story was actually skipped. A failed skip clears it.
enum NotInterestedFiling {
    static func clearsMark(skipLanded: Bool) -> Bool {
        !skipLanded
    }
}

enum NotInterestedLog {
    static let archiveFolderName = "Archive"
    static let keepLimit = 200

    @discardableResult
    static func record(_ article: Article, in context: ModelContext, now: Date = .now) throws -> NotInterestedEntry {
        let wasMarked = article.notInterested
        article.notInterested = true
        let url = ArticleIdentity.normalizedURLString(article.url)
        let existing = entries(matching: article, in: context).first
        let feed = article.feed
        let entry = existing ?? NotInterestedEntry(
            recordedAt: now,
            articleTitle: article.title,
            articleURL: url,
            articleGUID: article.guid,
            sourceTitle: feed?.title ?? ArticlePresentation.sourceName(for: article),
            sourceFeedURL: feed.map { ArticleIdentity.feedKey($0.feedURL) } ?? "",
            sourceWebsiteURL: feed?.websiteURL.flatMap { ArticleIdentity.normalizedURLString($0) },
            feedID: feed?.id
        )
        if existing == nil {
            context.insert(entry)
        }
        entry.recordedAt = now
        entry.articleTitle = article.title
        entry.articleURL = url
        entry.articleGUID = article.guid
        entry.sourceTitle = feed?.title ?? ArticlePresentation.sourceName(for: article)
        if let feed {
            entry.sourceFeedURL = ArticleIdentity.feedKey(feed.feedURL)
            entry.sourceWebsiteURL = feed.websiteURL.flatMap { ArticleIdentity.normalizedURLString($0) }
            entry.feedID = feed.id
        }
        trim(in: context)
        do {
            try context.save()
        } catch {
            context.rollback()
            article.notInterested = wasMarked
            throw error
        }
        return entry
    }

    static func entries(matching article: Article, in context: ModelContext) -> [NotInterestedEntry] {
        let guid = article.guid
        let byGUID = (try? context.fetch(
            FetchDescriptor<NotInterestedEntry>(predicate: #Predicate { $0.articleGUID == guid })
        )) ?? []
        guard let url = ArticleIdentity.normalizedURLString(article.url) else { return byGUID }
        let byURL = (try? context.fetch(
            FetchDescriptor<NotInterestedEntry>(predicate: #Predicate { $0.articleURL == url })
        )) ?? []
        var seen = Set(byGUID.map(\.id))
        return byGUID + byURL.filter { seen.insert($0.id).inserted }
    }

    /// How many marks exist. History only shows this number, so it does not load every title.
    static func count(in context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<NotInterestedEntry>())) ?? 0
    }

    nonisolated static func entries(in context: ModelContext) -> [NotInterestedEntry] {
        let descriptor = FetchDescriptor<NotInterestedEntry>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    nonisolated static func groups(from entries: [NotInterestedEntry]) -> [NotInterestedSourceGroup] {
        let plans = NotInterestedListPlan.groups(from: entries.map(NotInterestedEntrySnap.init))
        let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return plans.map { plan in
            NotInterestedSourceGroup(
                sourceTitle: plan.sourceTitle,
                sourceFeedURL: plan.sourceFeedURL,
                sourceWebsiteURL: plan.sourceWebsiteURL,
                feedID: plan.feedID,
                entries: plan.entryIDs.compactMap { byID[$0] }
            )
        }
    }

    nonisolated static func snapshot(in context: ModelContext, sources: Int = 12, articlesPerSource: Int = 3) -> String {
        let grouped = groups(from: entries(in: context))
        guard !grouped.isEmpty else {
            return "No articles have been marked not interested."
        }
        let feeds = (try? context.fetch(FetchDescriptor<Feed>())) ?? []
        var lines: [String] = [
            "Not interested (\(grouped.reduce(0) { $0 + $1.count }) marks, \(grouped.count) source\(grouped.count == 1 ? "" : "s")):"
        ]
        for group in grouped.prefix(sources) {
            let feed = feed(matching: group, in: feeds)
            var flags: [String] = []
            let folders = feed?.memberships ?? []
            if !folders.isEmpty {
                flags.append(folders.joined(separator: ", "))
            }
            if feed?.includeInToday == false { flags.append("not in Today") }
            if feed?.isEnabled == false { flags.append("paused") }
            if feed == nil { flags.append("source gone") }
            let suffix = flags.isEmpty ? "" : " — " + flags.joined(separator: ", ")
            lines.append("- \(group.sourceTitle) (\(group.count))\(suffix)")
            for entry in group.entries.prefix(articlesPerSource) {
                lines.append("  · \(entry.articleTitle) · \(entry.recordedAt.formatted(.dateTime.month(.abbreviated).day()))")
            }
            if group.count > articlesPerSource {
                lines.append("  · …and \(group.count - articlesPerSource) more")
            }
        }
        if grouped.count > sources {
            lines.append("…and \(grouped.count - sources) more sources. Call list_not_interested for the rest.")
        }
        return lines.joined(separator: "\n")
    }

    nonisolated static func reviewPrompt(in context: ModelContext) -> String {
        """
        Review my not-interested log. Group by source and notice repeats. Suggest moving a noisy source to Archive (keep the subscription, take it out of Today), adding blocked words, or removing it. Wait for me before removing anything.

        \(snapshot(in: context, sources: 16, articlesPerSource: 4))
        """
    }

    /// Builds the review prompt away from the main thread so opening the librarian can start immediately.
    static func reviewPrompt(from container: ModelContainer) async -> String {
        await Task.detached(priority: .userInitiated) {
            reviewPrompt(in: ModelContext(container))
        }.value
    }

    static func archive(_ feed: Feed, in context: ModelContext) throws {
        let memberships = feed.memberships
        let included = feed.includeInToday
        feed.setMemberships([Self.archiveFolderName])
        feed.includeInToday = false
        FolderStore.remember(archiveFolderName)
        LibraryChange.note(feed)
        do {
            try DailyDeckService.reconcileMembership(in: context)
        } catch {
            context.rollback()
            feed.setMemberships(memberships)
            feed.includeInToday = included
            throw error
        }
    }

    static func takeOutOfToday(_ feed: Feed, in context: ModelContext) throws {
        let included = feed.includeInToday
        feed.includeInToday = false
        LibraryChange.note(feed)
        do {
            try DailyDeckService.reconcileMembership(in: context)
        } catch {
            context.rollback()
            feed.includeInToday = included
            throw error
        }
    }

    static func delete(_ entry: NotInterestedEntry, in context: ModelContext) throws {
        context.delete(entry)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    nonisolated static func feed(matching group: NotInterestedSourceGroup, in feeds: [Feed]) -> Feed? {
        if let id = group.feedID, let feed = feeds.first(where: { $0.id == id }) {
            return feed
        }
        return feed(matchingFeedURL: group.sourceFeedURL, in: feeds)
    }

    /// The one source this group names. A refresh of other sources does not load them onto the log.
    static func storedFeed(matching group: NotInterestedSourceGroup, in context: ModelContext) -> Feed? {
        if let id = group.feedID, let feed = fetchFeed(id: id, in: context) { return feed }
        guard let id = feedID(matchingFeedURL: group.sourceFeedURL, in: context.container) else { return nil }
        return fetchFeed(id: id, in: context)
    }

    private static func fetchFeed(id: UUID, in context: ModelContext) -> Feed? {
        let match = id
        var descriptor = FetchDescriptor<Feed>(predicate: #Predicate { $0.id == match })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Matches an older mark that has no source id. The scan stays off the open screen.
    nonisolated static func feedID(matchingFeedURL raw: String, in container: ModelContainer) -> UUID? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var descriptor = FetchDescriptor<Feed>()
        descriptor.propertiesToFetch = [\.id, \.feedURL]
        let feeds = (try? context.fetch(descriptor)) ?? []
        return feed(matchingFeedURL: trimmed, in: feeds)?.id
    }

    nonisolated static func feed(matchingFeedURL raw: String, in feeds: [Feed]) -> Feed? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed) {
            let key = ArticleIdentity.feedKey(url)
            if let feed = feeds.first(where: { ArticleIdentity.feedKey($0.feedURL) == key }) {
                return feed
            }
        }
        return feeds.first { $0.feedURL.absoluteString.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    /// One lookup for the log, so opening the list does not fetch once per row.
    nonisolated static func articles(matchingGUIDs guids: [String], in context: ModelContext) -> [String: Article] {
        let keys = guids.filter { !$0.isEmpty }
        guard !keys.isEmpty else { return [:] }
        let found = (try? context.fetch(ArticleListFetch.rows(predicate: #Predicate { keys.contains($0.guid) }))) ?? []
        var byGUID: [String: Article] = [:]
        for article in found where !article.guid.isEmpty {
            byGUID[article.guid] = article
        }
        return byGUID
    }

    static func article(for entry: NotInterestedEntry, in context: ModelContext) -> Article? {
        let guid = entry.articleGUID
        if !guid.isEmpty {
            var descriptor = ArticleListFetch.rows(predicate: #Predicate { $0.guid == guid })
            descriptor.fetchLimit = 1
            if let match = try? context.fetch(descriptor).first { return match }
        }
        guard let rawURL = entry.articleURL, let parsed = URL(string: rawURL) else { return nil }
        return ArticleIdentity.storedArticle(matching: parsed, in: context)
    }

    private static func trim(in context: ModelContext) {
        let descriptor = FetchDescriptor<NotInterestedEntry>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        guard let all = try? context.fetch(descriptor), all.count > keepLimit else { return }
        for extra in all.dropFirst(keepLimit) {
            context.delete(extra)
        }
    }
}

struct NotInterestedEntrySnap: Sendable {
    var id: UUID
    var recordedAt: Date
    var sourceTitle: String
    var sourceFeedURL: String
    var sourceWebsiteURL: String?
    var feedID: UUID?

    init(
        id: UUID,
        recordedAt: Date,
        sourceTitle: String,
        sourceFeedURL: String,
        sourceWebsiteURL: String?,
        feedID: UUID?
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.sourceTitle = sourceTitle
        self.sourceFeedURL = sourceFeedURL
        self.sourceWebsiteURL = sourceWebsiteURL
        self.feedID = feedID
    }

    init(_ entry: NotInterestedEntry) {
        id = entry.id
        recordedAt = entry.recordedAt
        sourceTitle = entry.sourceTitle
        sourceFeedURL = entry.sourceFeedURL
        sourceWebsiteURL = entry.sourceWebsiteURL
        feedID = entry.feedID
    }
}

struct NotInterestedGroupPlan: Sendable {
    var sourceTitle: String
    var sourceFeedURL: String
    var sourceWebsiteURL: String?
    var feedID: UUID?
    var entryIDs: [UUID]
}

/// Same source groups as the Not interested log, from copied fields.
nonisolated enum NotInterestedListPlan {
    /// A modest log can be grouped on the open screen. A long one waits for the off-screen plan.
    static let synchronousGroupingLimit = 200

    static func groupsOnTheOpenScreen(entryCount: Int) -> Bool {
        entryCount > 0 && entryCount <= synchronousGroupingLimit
    }

    /// A modest log can look up its stories before the rows draw. A long log looks up a row when it appears.
    static func prefetchesStories(entryCount: Int) -> Bool {
        entryCount <= synchronousGroupingLimit
    }

    /// Copies marks on a short-lived context. A long log uses this instead of walking the rows on screen.
    static func snaps(in container: ModelContainer) -> [NotInterestedEntrySnap] {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var descriptor = FetchDescriptor<NotInterestedEntry>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        descriptor.propertiesToFetch = [
            \.id, \.recordedAt, \.sourceTitle, \.sourceFeedURL, \.sourceWebsiteURL, \.feedID,
        ]
        let entries = (try? context.fetch(descriptor)) ?? []
        return entries.map { entry in
            NotInterestedEntrySnap(
                id: entry.id,
                recordedAt: entry.recordedAt,
                sourceTitle: entry.sourceTitle,
                sourceFeedURL: entry.sourceFeedURL,
                sourceWebsiteURL: entry.sourceWebsiteURL,
                feedID: entry.feedID
            )
        }
    }

    static func groups(from snaps: [NotInterestedEntrySnap]) -> [NotInterestedGroupPlan] {
        var order: [String] = []
        var buckets: [String: [NotInterestedEntrySnap]] = [:]
        for snap in snaps {
            let key = snap.sourceFeedURL.isEmpty ? snap.sourceTitle.lowercased() : snap.sourceFeedURL
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(snap)
        }
        return order.map { key in
            let items = (buckets[key] ?? []).sorted { $0.recordedAt > $1.recordedAt }
            let first = items[0]
            return NotInterestedGroupPlan(
                sourceTitle: first.sourceTitle,
                sourceFeedURL: first.sourceFeedURL,
                sourceWebsiteURL: first.sourceWebsiteURL,
                feedID: first.feedID,
                entryIDs: items.map(\.id)
            )
        }
        .sorted { lhs, rhs in
            if lhs.entryIDs.count != rhs.entryIDs.count { return lhs.entryIDs.count > rhs.entryIDs.count }
            return lhs.sourceTitle.localizedCaseInsensitiveCompare(rhs.sourceTitle) == .orderedAscending
        }
    }
}
