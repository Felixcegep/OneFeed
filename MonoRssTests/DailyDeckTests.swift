import Foundation
import SwiftData
import Testing
@testable import MonoRss

@MainActor
struct DailyDeckTests {
    private func context() throws -> ModelContext {
        try InMemoryStore.makeContext()
    }

    @Test func generateCreatesAtMostTenItems() throws {
        let context = try context()
        for index in 0..<12 {
            let feed = Feed(title: "Source \(index)", feedURL: URL(string: "https://source-\(index).test/rss")!)
            context.insert(feed)
            context.insert(Article(
                guid: "article-\(index)",
                title: "Article \(index)",
                publishedAt: .now.addingTimeInterval(Double(-index * 60)),
                feed: feed
            ))
        }

        let deck = try DailyDeckService().generateIfNeeded(in: context)
        #expect(deck.items.count == 10)
    }

    @Test func sourceRotationLimitsItemsPerFeed() throws {
        let context = try context()
        let feedA = Feed(title: "A", feedURL: URL(string: "https://a.test/rss")!)
        let feedB = Feed(title: "B", feedURL: URL(string: "https://b.test/rss")!)
        context.insert(feedA)
        context.insert(feedB)
        for index in 0..<8 {
            context.insert(Article(
                guid: "a-\(index)",
                title: "A \(index)",
                publishedAt: .now.addingTimeInterval(Double(-index * 30)),
                feed: feedA
            ))
            context.insert(Article(
                guid: "b-\(index)",
                title: "B \(index)",
                publishedAt: .now.addingTimeInterval(Double(-index * 30 - 5)),
                feed: feedB
            ))
        }

        let deck = try DailyDeckService().generateIfNeeded(in: context)
        let counts = Dictionary(grouping: deck.items.compactMap(\.article?.feed?.id), by: { $0 }).mapValues(\.count)
        #expect(counts.values.allSatisfy { $0 <= 2 })
        #expect(counts.count == 2)
    }

    @Test func secondGenerateSameDayReturnsFrozenDeck() throws {
        let context = try context()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        context.insert(feed)
        context.insert(Article(guid: "one", title: "One", publishedAt: .now.addingTimeInterval(-60), feed: feed))

        let service = DailyDeckService()
        let first = try service.generateIfNeeded(in: context)
        context.insert(Article(guid: "two", title: "Two", publishedAt: .now, feed: feed))
        let second = try service.generateIfNeeded(in: context)

        #expect(first.id == second.id)
        #expect(second.items.count == 1)
    }

    @Test func advanceMovesToNextItemAndMarksFirstDone() throws {
        let context = try context()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        context.insert(feed)
        let older = Article(guid: "one", title: "One", publishedAt: .now.addingTimeInterval(-120), feed: feed)
        let newer = Article(guid: "two", title: "Two", publishedAt: .now.addingTimeInterval(-60), feed: feed)
        context.insert(older)
        context.insert(newer)

        let deck = try DailyDeckService().generateIfNeeded(in: context)
        #expect(deck.items.count == 2)
        let firstItem = try #require(deck.items.sorted { $0.position < $1.position }.first)
        #expect(firstItem.article?.guid == newer.guid)
        let next = try DailyDeckService().advance(item: firstItem, to: .read, in: context)

        #expect(firstItem.status == .read)
        #expect(firstItem.article?.state == .read)
        #expect(firstItem.article?.completedAt != nil)
        #expect(next?.article?.guid == older.guid)
        #expect(next?.article?.state == .current)
    }

    @Test func fewerThanTenItemsIsAllowed() throws {
        let context = try context()
        for index in 0..<3 {
            let feed = Feed(title: "Source \(index)", feedURL: URL(string: "https://source-\(index).test/rss")!)
            context.insert(feed)
            context.insert(Article(
                guid: "article-\(index)",
                title: "Article \(index)",
                publishedAt: .now.addingTimeInterval(Double(-index * 120)),
                feed: feed
            ))
        }

        let deck = try DailyDeckService().generateIfNeeded(in: context)
        #expect(deck.items.count == 3)
        #expect(deck.items.count <= 10)
    }
}
