import Foundation
import SwiftData

enum NotInterestedLog {
    static let archiveFolderName = "Archive"
    static let keepLimit = 200

    @discardableResult
    static func record(_ article: Article, in context: ModelContext, now: Date = .now) -> NotInterestedEntry {
        article.notInterested = true
        let url = ArticleIdentity.normalizedURLString(article.url)
        let existing = (try? context.fetch(FetchDescriptor<NotInterestedEntry>()))?.first { entry in
            entry.articleGUID == article.guid
                || (url != nil && entry.articleURL == url)
        }
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
        try? context.save()
        return entry
    }

    static func entries(in context: ModelContext) -> [NotInterestedEntry] {
        let descriptor = FetchDescriptor<NotInterestedEntry>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func groups(from entries: [NotInterestedEntry]) -> [NotInterestedSourceGroup] {
        var order: [String] = []
        var buckets: [String: [NotInterestedEntry]] = [:]
        for entry in entries {
            let key = entry.sourceFeedURL.isEmpty ? entry.sourceTitle.lowercased() : entry.sourceFeedURL
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(entry)
        }
        return order.map { key in
            let items = (buckets[key] ?? []).sorted { $0.recordedAt > $1.recordedAt }
            let first = items[0]
            return NotInterestedSourceGroup(
                sourceTitle: first.sourceTitle,
                sourceFeedURL: first.sourceFeedURL,
                sourceWebsiteURL: first.sourceWebsiteURL,
                feedID: first.feedID,
                entries: items
            )
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.sourceTitle.localizedCaseInsensitiveCompare(rhs.sourceTitle) == .orderedAscending
        }
    }

    static func snapshot(in context: ModelContext, sources: Int = 12, articlesPerSource: Int = 3) -> String {
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
            if let folder = feed?.folderName?.trimmingCharacters(in: .whitespacesAndNewlines), !folder.isEmpty {
                flags.append(folder)
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

    static func reviewPrompt(in context: ModelContext) -> String {
        """
        Review my not-interested log. Group by source and notice repeats. Suggest moving a noisy source to Archive (keep the subscription, take it out of Today), adding blocked words, or removing it. Wait for me before removing anything.

        \(snapshot(in: context, sources: 16, articlesPerSource: 4))
        """
    }

    static func archive(_ feed: Feed, in context: ModelContext) {
        feed.folderName = archiveFolderName
        feed.includeInToday = false
        FolderStore.remember(archiveFolderName)
        LibraryChange.note(feed)
        try? context.save()
    }

    static func takeOutOfToday(_ feed: Feed, in context: ModelContext) {
        feed.includeInToday = false
        LibraryChange.note(feed)
        try? context.save()
    }

    static func delete(_ entry: NotInterestedEntry, in context: ModelContext) {
        context.delete(entry)
        try? context.save()
    }

    static func feed(matching group: NotInterestedSourceGroup, in feeds: [Feed]) -> Feed? {
        if let id = group.feedID, let feed = feeds.first(where: { $0.id == id }) {
            return feed
        }
        return feed(matchingFeedURL: group.sourceFeedURL, in: feeds)
    }

    static func feed(matchingFeedURL raw: String, in feeds: [Feed]) -> Feed? {
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

    static func article(for entry: NotInterestedEntry, in context: ModelContext) -> Article? {
        let guid = entry.articleGUID
        if !guid.isEmpty {
            let descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.guid == guid })
            if let match = try? context.fetch(descriptor).first { return match }
        }
        guard let url = entry.articleURL, !url.isEmpty else { return nil }
        return (try? context.fetch(FetchDescriptor<Article>()))?.first {
            ArticleIdentity.normalizedURLString($0.url) == url
        }
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
