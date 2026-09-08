import Foundation
import SwiftData
import Testing
@testable import MonoRss

@MainActor
struct FeedSeedTests {
    @Test func catalogIncludesCadenceAndTopicFolders() {
        #expect(FeedSeedCatalog.feeds.count == 60)
        #expect(Set(FeedSeedCatalog.feeds.map(\.url)).count == 60)
        #expect(FeedSeedCatalog.folderOrder == [
            "Must read", "Builders", "Philosophy", "Programming & Software",
            "Security & Systems", "Business", "Geopolitics", "Fitness",
            "Entertainment", "À scanner", "Papers",
        ])
        #expect(FeedSeedCatalog.feeds.contains { $0.title == "Stratechery" } == false)
        #expect(FeedSeedCatalog.isRetired(title: "Stratechery by Ben Thompson", url: URL(string: "https://stratechery.com/feed/")))
        #expect(FeedSeedCatalog.feeds.first { $0.title == "Simon Willison" }?.folder == "Must read")
        #expect(FeedSeedCatalog.feeds.contains { $0.title == "Simon Willison" && $0.folder == "Programming & Software" } == false)
        #expect(FeedSeedCatalog.feeds.first { $0.title == "Interconnects AI" }?.folder == "Must read")
        #expect(FeedSeedCatalog.feeds.first { $0.title == "Hacker News" }?.folder == "À scanner")
        #expect(FeedSeedCatalog.feeds.first { $0.title == "Trail of Bits" }?.folder == "Security & Systems")
        #expect(FeedSeedCatalog.feeds.first { $0.title == "Art Chad" }?.contentKind == "youtube")
        #expect(CuratedReadingCatalog.feeds.count == 18)
    }

    @Test func applyingCatalogInsertsThenIsIdempotentAndDropsRetired() throws {
        let context = try InMemoryStore.makeContext()
        context.insert(Feed(
            title: "Gone",
            feedURL: URL(string: "https://acephale.substack.com/feed")!,
            folderName: "Philosophy"
        ))

        let first = try FeedSeedService().apply(in: context)
        #expect(first.inserted == 60)
        #expect(first.removed == 1)
        #expect(try context.fetchCount(FetchDescriptor<Feed>()) == 60)

        let second = try FeedSeedService().apply(in: context)
        #expect(second.inserted == 0)
        #expect(second.removed == 0)
        #expect(try context.fetchCount(FetchDescriptor<Feed>()) == 60)

        let misplaced = try #require(context.fetch(FetchDescriptor<Feed>()).first { $0.title == "Aeon" })
        misplaced.folderName = "Unfiled"
        let third = try FeedSeedService().apply(in: context)
        #expect(third.updated == 1)
        #expect(misplaced.folderName == "Philosophy")
    }

    @Test func applyingCatalogRemovesStratecheryByTitleOrURL() throws {
        let context = try InMemoryStore.makeContext()
        context.insert(Feed(
            title: "Stratechery by Ben Thompson",
            feedURL: URL(string: "https://stratechery.com/feed/")!
        ))
        let removed = try FeedSeedService().removeRetired(in: context)
        #expect(removed == 1)
        #expect(try context.fetch(FetchDescriptor<Feed>()).isEmpty)
    }

    @Test func curatedReadingPackCreatesCadenceFolders() throws {
        let context = try InMemoryStore.makeContext()
        let result = try FeedSeedService().applyCuratedReadingPack(in: context)
        #expect(result.inserted == 18)
        let feeds = try context.fetch(FetchDescriptor<Feed>())
        #expect(Set(feeds.compactMap(\.folderName)) == Set(CuratedReadingCatalog.folderOrder))
        #expect(feeds.contains { $0.title == "Interconnects AI" && $0.folderName == "Must read" })
        #expect(feeds.contains { $0.title == "Hacker News" && $0.folderName == "À scanner" })

        let second = try FeedSeedService().applyCuratedReadingPack(in: context)
        #expect(second.inserted == 0)
        #expect(second.updated == 0)
    }

    @Test func folderGroupingUsesSeededOrder() {
        let must = Feed(title: "A", feedURL: URL(string: "https://a.test/rss")!, folderName: "Must read")
        let papers = Feed(title: "B", feedURL: URL(string: "https://b.test/rss")!, folderName: "Papers")
        let philosophy = Feed(title: "C", feedURL: URL(string: "https://c.test/rss")!, folderName: "Philosophy")
        let names = FeedFolderGrouping.groups(from: [papers, philosophy, must]).map(\.name)
        #expect(names == ["Must read", "Philosophy", "Papers"])
    }
}
