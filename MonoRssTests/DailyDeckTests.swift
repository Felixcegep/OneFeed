import Foundation
import SwiftData
import Testing
@testable import OneFeed

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

    @Test func sourcesLeftOutOfTodayAreNotSelected() throws {
        let context = try context()
        let included = Feed(title: "Included", feedURL: URL(string: "https://in.test/rss")!, includeInToday: true)
        let excluded = Feed(title: "Excluded", feedURL: URL(string: "https://out.test/rss")!, includeInToday: false)
        context.insert(included)
        context.insert(excluded)
        context.insert(Article(guid: "in", title: "In", publishedAt: .now.addingTimeInterval(-60), feed: included))
        context.insert(Article(guid: "out", title: "Out", publishedAt: .now, feed: excluded))

        let deck = try DailyDeckService().generateIfNeeded(in: context)
        #expect(deck.items.count == 1)
        #expect(deck.items.first?.article?.guid == "in")
    }

    @Test func turningASourceOffRemovesItsOpenStoryAndPromotesTheNext() throws {
        let context = try context()
        let keep = Feed(title: "Keep", feedURL: URL(string: "https://keep.test/rss")!)
        let drop = Feed(title: "Drop", feedURL: URL(string: "https://drop.test/rss")!)
        context.insert(keep)
        context.insert(drop)
        let kept = Article(guid: "keep", title: "Keep", publishedAt: .now.addingTimeInterval(-60), feed: keep)
        let dropped = Article(guid: "drop", title: "Drop", publishedAt: .now, feed: drop)
        context.insert(kept)
        context.insert(dropped)

        let deck = try DailyDeckService().generateIfNeeded(in: context)
        #expect(dropped.state == .current)
        #expect(kept.state == .queued)

        try DailyDeckService.setIncludedInToday(false, feeds: [drop], in: context)

        let remaining = try DailyDeckService().remainingArticles(in: context)
        #expect(remaining.map(\.guid) == ["keep"])
        #expect(kept.state == .current)
        #expect(dropped.state == .queued)
        #expect(dropped.isStored)
        #expect(try DailyDeckService.todayDeck(in: context)?.items.count == 1)
    }

    @Test func turningASourceOnFillsAnOpenSlot() throws {
        let context = try context()
        let first = Feed(title: "First", feedURL: URL(string: "https://first.test/rss")!)
        let second = Feed(title: "Second", feedURL: URL(string: "https://second.test/rss")!, includeInToday: false)
        context.insert(first)
        context.insert(second)
        context.insert(Article(guid: "one", title: "One", publishedAt: .now, feed: first))
        context.insert(Article(guid: "two", title: "Two", publishedAt: .now.addingTimeInterval(-30), feed: second))

        let deck = try DailyDeckService().generateIfNeeded(in: context)
        #expect(deck.items.count == 1)

        try DailyDeckService.setIncludedInToday(true, feeds: [second], in: context)

        let items = try #require(try DailyDeckService.todayDeck(in: context)).items
        #expect(items.count == 2)
        #expect(items.contains { $0.article?.guid == "two" })
    }

    @Test func finishedStoriesStayWhenTheirSourceLeavesToday() throws {
        let context = try context()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        let other = Feed(title: "Other", feedURL: URL(string: "https://other.test/rss")!)
        context.insert(feed)
        context.insert(other)
        let done = Article(guid: "done", title: "Done", publishedAt: .now, feed: feed)
        let waiting = Article(guid: "waiting", title: "Waiting", publishedAt: .now.addingTimeInterval(-60), feed: other)
        context.insert(done)
        context.insert(waiting)

        let deck = try DailyDeckService().generateIfNeeded(in: context)
        let first = try #require(deck.items.sorted { $0.position < $1.position }.first)
        _ = try DailyDeckService().advance(item: first, to: .read, in: context)
        #expect(done.state == .read)

        try DailyDeckService.setIncludedInToday(false, feeds: [feed], in: context)

        let items = try #require(try DailyDeckService.todayDeck(in: context)).items.sorted { $0.position < $1.position }
        #expect(done.state == .read)
        #expect(items.contains { $0.article?.guid == "done" && $0.status == .read })
        #expect(items.contains { $0.article?.guid == "waiting" && $0.status == .current })
        #expect(items.map(\.position) == Array(1...items.count))
    }
}
