import Foundation
import SwiftData
import Testing
@testable import OneFeed

@MainActor
struct ContentMemoryTests {
    @Test func packUnpackRoundTripPreservesValues() {
        let values = [0.0, -1.5, 0.125, 3.14159, 1e-4]
        let unpacked = ContentVector.unpack(ContentVector.pack(values))
        let decoded = unpacked ?? []
        #expect(unpacked != nil)
        #expect(decoded.count == values.count)
        for (original, restored) in zip(values, decoded) {
            #expect(abs(original - restored) < 1e-5)
        }
    }

    @Test func memorySurvivesArticleRetentionPurge() throws {
        let context = try InMemoryStore.makeContext()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        context.insert(feed)
        let memory = ContentMemory(
            identityKey: "url:https://source.test/old",
            canonicalURL: "https://source.test/old",
            sourceType: "article",
            title: "Old story",
            itemDescription: "An excerpt that should outlive the article row.",
            semanticText: "Old story\nAn excerpt that should outlive the article row."
        )
        context.insert(memory)
        let article = Article(
            guid: "old",
            title: "Old story",
            url: URL(string: "https://source.test/old"),
            publishedAt: .now.addingTimeInterval(-10 * 86_400),
            state: .read,
            readingNote: "",
            feed: feed
        )
        context.insert(article)
        try context.save()

        let removed = try ArticleRetentionService().purge(
            in: context,
            olderThanDays: ArticleRetentionService.defaultRetentionDays
        )
        #expect(removed == 1)
        #expect(try context.fetch(FetchDescriptor<Article>()).isEmpty)
        let memories = try context.fetch(FetchDescriptor<ContentMemory>())
        #expect(memories.count == 1)
        #expect(memories.first?.id == memory.id)
        #expect(memories.first?.identityKey == "url:https://source.test/old")
        #expect(memories.first?.semanticText == memory.semanticText)
    }
}
