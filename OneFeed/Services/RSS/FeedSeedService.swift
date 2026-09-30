import Foundation
import SwiftData

/// The catalog is applied after the first screen can appear. A later launch only drops retired sources.
enum LaunchSeed {
    static func needsApply(seededVersion: Int, legacySeeded: Bool, catalogVersion: Int = FeedSeedCatalog.version) -> Bool {
        seededVersion < catalogVersion || !legacySeeded
    }
}

struct FeedSeedResult: Equatable {
    var inserted = 0
    var updated = 0
    var removed = 0
}

@MainActor
struct FeedSeedService {
    /// Inserts every catalog feed, realigns folders/titles, and drops retired URLs.
    func apply(in context: ModelContext) throws -> FeedSeedResult {
        try apply(entries: FeedSeedCatalog.feeds, in: context, removeRetired: true)
    }

    /// Cadence folders only (Must read / Builders / À scanner / Papers).
    func applyCuratedReadingPack(in context: ModelContext) throws -> FeedSeedResult {
        try apply(entries: CuratedReadingCatalog.feeds, in: context, removeRetired: false)
    }

    /// Drops sources that left the catalog, including on launches after the first seed.
    func removeRetired(in context: ModelContext) throws -> Int {
        var existing = Dictionary(
            uniqueKeysWithValues: (try context.fetch(FetchDescriptor<Feed>())).map { ($0.feedURL.absoluteString, $0) }
        )
        let removed = removeRetiredFeeds(from: &existing, in: context)
        if removed > 0 { try context.save() }
        return removed
    }

    private func apply(entries: [FeedSeedCatalog.Entry], in context: ModelContext, removeRetired: Bool) throws -> FeedSeedResult {
        var result = FeedSeedResult()
        let existing = try context.fetch(FetchDescriptor<Feed>())
        var byURL = Dictionary(uniqueKeysWithValues: existing.map { ($0.feedURL.absoluteString, $0) })

        if removeRetired {
            result.removed = removeRetiredFeeds(from: &byURL, in: context)
        }

        for entry in entries {
            let key = entry.url.absoluteString
            if let feed = byURL[key] {
                var changed = false
                if feed.addFolder(entry.folder) {
                    changed = true
                }
                if feed.title != entry.title {
                    feed.title = entry.title
                    changed = true
                }
                if feed.contentKind != entry.contentKind {
                    feed.contentKind = entry.contentKind
                    changed = true
                }
                if changed { result.updated += 1 }
                continue
            }
            let feed = Feed(
                title: entry.title,
                feedURL: entry.url,
                folderName: entry.folder,
                contentKind: entry.contentKind
            )
            context.insert(feed)
            byURL[key] = feed
            result.inserted += 1
        }

        FolderStore.remember(FeedSeedCatalog.folderOrder)
        FolderStore.remember(entries.map(\.folder))

        if result.inserted > 0 || result.updated > 0 || result.removed > 0 {
            try context.save()
        }
        return result
    }

    private func removeRetiredFeeds(from byURL: inout [String: Feed], in context: ModelContext) -> Int {
        var removed = 0
        for (url, feed) in byURL {
            guard FeedSeedCatalog.isRetired(title: feed.title, url: feed.feedURL) else { continue }
            LibraryChange.noteRemovedFeed(feed)
            context.delete(feed)
            byURL[url] = nil
            removed += 1
        }
        return removed
    }
}
