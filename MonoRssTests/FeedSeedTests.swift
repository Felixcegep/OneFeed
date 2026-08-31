import Foundation
import SwiftData
import Testing
@testable import MonoRss

@MainActor
struct FeedSeedTests {
    @Test func catalogMatchesTinyRSSFoldersAndMarksYouTube() {
        #expect(FeedSeedCatalog.feeds.count == 44)
        #expect(Set(FeedSeedCatalog.feeds.map(\.url)).count == 44)
        let philosophy = FeedSeedCatalog.feeds.filter { $0.folder == "Philosophy" }
        #expect(philosophy.contains { $0.url.absoluteString == "https://1000wordphilosophy.com/feed/" })
        #expect(philosophy.contains { $0.contentKind == "youtube" && $0.title == "Art Chad" })
        #expect(FeedSeedCatalog.feeds.first { $0.title == "Trail of Bits" }?.folder == "Security & Systems")
        #expect(FeedSeedCatalog.feeds.first { $0.title == "Trail of Bits" }?.contentKind == "article")
    }

    @Test func applyingCatalogInsertsThenIsIdempotentAndDropsRetired() throws {
        let context = try InMemoryStore.makeContext()
        context.insert(Feed(
            title: "Gone",
            feedURL: URL(string: "https://acephale.substack.com/feed")!,
            folderName: "Philosophy"
        ))

        let first = try FeedSeedService().apply(in: context)
        #expect(first.inserted == 44)
        #expect(first.removed == 1)
        #expect(try context.fetchCount(FetchDescriptor<Feed>()) == 44)

        let second = try FeedSeedService().apply(in: context)
        #expect(second.inserted == 0)
        #expect(second.removed == 0)
        #expect(try context.fetchCount(FetchDescriptor<Feed>()) == 44)

        let misplaced = try #require(context.fetch(FetchDescriptor<Feed>()).first { $0.title == "Aeon" })
        misplaced.folderName = "Unfiled"
        let third = try FeedSeedService().apply(in: context)
        #expect(third.updated == 1)
        #expect(misplaced.folderName == "Philosophy")
    }
}
