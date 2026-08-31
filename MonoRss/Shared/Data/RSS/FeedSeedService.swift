import Foundation
import SwiftData

struct FeedSeedResult: Equatable {
    var inserted = 0
    var updated = 0
    var removed = 0
}

@MainActor
struct FeedSeedService {
    /// Inserts missing catalog feeds, keeps folders aligned, and drops retired URLs.
    func apply(in context: ModelContext) throws -> FeedSeedResult {
        var result = FeedSeedResult()
        let existing = try context.fetch(FetchDescriptor<Feed>())
        var byURL = Dictionary(uniqueKeysWithValues: existing.map { ($0.feedURL.absoluteString, $0) })

        for url in FeedSeedCatalog.retiredFeedURLs {
            guard let feed = byURL[url] else { continue }
            context.delete(feed)
            byURL[url] = nil
            result.removed += 1
        }

        for entry in FeedSeedCatalog.feeds {
            let key = entry.url.absoluteString
            if let feed = byURL[key] {
                var changed = false
                if feed.folderName != entry.folder {
                    feed.folderName = entry.folder
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

        if result.inserted > 0 || result.updated > 0 || result.removed > 0 {
            try context.save()
        }
        return result
    }
}
