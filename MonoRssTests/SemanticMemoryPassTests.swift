import Foundation
import SwiftData
import Testing
@testable import OneFeed

@MainActor
struct SemanticMemoryPassTests {
    @Test func prepareStoresOneMemoryThenMarksItConsumed() async throws {
        let context = try InMemoryStore.makeContext()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        let article = Article(
            guid: "hello",
            title: "Hello",
            url: URL(string: "https://example.com/story"),
            publishedAt: .now,
            feed: feed
        )
        context.insert(feed)
        context.insert(article)

        try await SemanticMemoryPass.prepare(in: context)

        let first = try context.fetch(FetchDescriptor<ContentMemory>())
        #expect(first.count == 1)
        let memory = try #require(first.first)
        #expect(memory.identityKey.hasPrefix("url:"))
        #expect(memory.identityKey.contains("example.com/story"))
        #expect(memory.identityKey == ArticleIdentity.identityKey(for: article))
        #expect(
            memory.stateRaw == SemanticState.raw.rawValue
                || memory.stateRaw == SemanticState.preliminary.rawValue
        )

        try await SemanticMemoryPass.prepare(in: context)
        let second = try context.fetch(FetchDescriptor<ContentMemory>())
        #expect(second.count == 1)

        let completed = Date(timeIntervalSince1970: 1_700_000_000)
        article.state = .read
        article.completedAt = completed
        try await SemanticMemoryPass.prepare(in: context)

        let third = try context.fetch(FetchDescriptor<ContentMemory>())
        #expect(third.count == 1)
        #expect(third.first?.consumedAt != nil)
    }
}
