import Foundation
import SwiftData
import Testing
@testable import OneFeed

@MainActor
struct ArticleStateTests {
    private func context() throws -> ModelContext {
        try InMemoryStore.makeContext()
    }

    @Test func choosingTheNextStoryKeepsBodiesOnDisk() throws {
        let container = try InMemoryStore.makeContainer()
        let setup = ModelContext(container)
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        setup.insert(feed)
        let body = "<p>" + String(repeating: "word ", count: 400) + "</p>"
        let current = Article(guid: "current", title: "Current", contentHTML: body, state: .current, feed: feed)
        let next = Article(
            guid: "next",
            title: "Next",
            publishedAt: .now.addingTimeInterval(10),
            contentHTML: body,
            feed: feed
        )
        let later = Article(
            guid: "later",
            title: "Later",
            publishedAt: .now.addingTimeInterval(20),
            contentHTML: body,
            feed: feed
        )
        setup.insert(current)
        setup.insert(next)
        setup.insert(later)
        try setup.save()

        let context = ModelContext(container)
        let currentValue = ArticleState.current.rawValue
        let storedCurrent = try #require(
            try context.fetch(FetchDescriptor<Article>(predicate: #Predicate { $0.stateRawValue == currentValue })).first
        )
        let replacement = try ArticleQueueService().transition(storedCurrent, to: .skipped, in: context)
        #expect(replacement?.guid == "next")
        #expect(replacement?.contentHTML == body)
        let laterID = later.id
        let storedLater = try #require(
            try context.fetch(FetchDescriptor<Article>(predicate: #Predicate { $0.id == laterID })).first
        )
        #expect(storedLater.contentHTML == body)
    }

    @Test func duplicateCurrentArticlesAreRepairedToOneCurrent() throws {
        let context = try context()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        context.insert(feed)
        let first = Article(guid: "first", title: "First", publishedAt: .now.addingTimeInterval(-20), state: .current, feed: feed)
        first.firstDisplayedAt = .now.addingTimeInterval(-10)
        let second = Article(guid: "second", title: "Second", publishedAt: .now, state: .current, feed: feed)
        second.firstDisplayedAt = .now
        context.insert(first)
        context.insert(second)

        let selected = try ArticleQueueService().ensureCurrent(in: context)
        #expect(selected === first)
        #expect(first.state == .current)
        #expect(second.state == .queued)
        let current = ArticleState.current.rawValue
        #expect(try context.fetchCount(FetchDescriptor<Article>(predicate: #Predicate { $0.stateRawValue == current })) == 1)
    }

    @Test func skipAdvancesWithoutMarkingArticleAsSaved() throws {
        let context = try context()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        context.insert(feed)
        let current = Article(guid: "current", title: "Current", state: .current, feed: feed)
        let next = Article(guid: "next", title: "Next", publishedAt: .now.addingTimeInterval(10), feed: feed)
        context.insert(current)
        context.insert(next)

        let replacement = try ArticleQueueService().transition(current, to: .skipped, in: context)
        #expect(current.state == .skipped)
        #expect(!current.isRemoteStarred)
        #expect(current.completedAt != nil)
        #expect(replacement === next)
        #expect(next.state == .current)
    }

    @Test func restoringSavedArticleReturnsItToQueue() throws {
        let context = try context()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        context.insert(feed)
        let saved = Article(guid: "saved", title: "Saved", state: .saved, isRemoteStarred: true, feed: feed)
        let other = Article(guid: "other", title: "Other", publishedAt: .now.addingTimeInterval(10), feed: feed)
        context.insert(saved)
        context.insert(other)

        try ArticleQueueService().restoreSaved(saved, in: context)
        #expect(saved.state == .current)
        #expect(!saved.isRemoteStarred)
        #expect(saved.completedAt == nil)
        #expect(other.state == .queued)
    }

    @Test func completingAQueuedArticleDoesNotRequireItToBeCurrent() throws {
        let context = try context()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        context.insert(feed)
        let current = Article(guid: "current", title: "Current", state: .current, feed: feed)
        let queued = Article(guid: "queued", title: "Queued", publishedAt: .now.addingTimeInterval(10), feed: feed)
        context.insert(current)
        context.insert(queued)

        try ArticleQueueService().complete(queued, as: .read, in: context)
        #expect(queued.state == .read)
        #expect(current.state == .current)
    }

    @Test func readingALaterArticleLeavesTheQueueButKeepsStarred() throws {
        let context = try context()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        context.insert(feed)
        let saved = Article(guid: "saved", title: "Saved", state: .saved, isRemoteStarred: true, feed: feed)
        context.insert(saved)

        try ArticleQueueService().complete(saved, as: .read, in: context)
        #expect(saved.state == .read)
        #expect(saved.isRemoteStarred)
        #expect(FeedFolderGrouping.savedArticles(from: [saved]).isEmpty)
    }

    @Test func moveToQueueKeepsNoteRatingAndClearsNotInterested() throws {
        let context = try context()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        context.insert(feed)
        let finished = Date(timeIntervalSince1970: 1_700_000_000)
        let article = Article(
            guid: "read-note",
            title: "Read with a note",
            url: URL(string: "https://source.test/read-note"),
            state: .read,
            rating: 4,
            notInterested: true,
            readingNote: "The nonce repeats.",
            feed: feed
        )
        article.completedAt = finished
        context.insert(article)
        try NotInterestedLog.record(article, in: context)
        let unrelated = NotInterestedEntry(
            articleTitle: "Something else",
            articleURL: "https://source.test/other",
            articleGUID: "other-guid",
            sourceTitle: "Source",
            sourceFeedURL: "https://source.test/rss"
        )
        context.insert(unrelated)
        try context.save()

        try ArticleQueueService().moveToQueue(article, in: context)

        #expect(article.state == .saved)
        #expect(article.readingNote == "The nonce repeats.")
        #expect(article.rating == 4)
        #expect(!article.notInterested)
        #expect(article.isRemoteStarred)
        #expect(article.completedAt == finished)
        let entries = try context.fetch(FetchDescriptor<NotInterestedEntry>())
        #expect(entries.map(\.articleGUID) == ["other-guid"])
    }

    @Test func moveToQueueClearsNotInterestedWhenAlreadySaved() throws {
        let context = try context()
        let article = Article(
            guid: "saved-aside",
            title: "Already queued",
            url: URL(string: "https://source.test/saved-aside"),
            state: .saved,
            notInterested: true
        )
        context.insert(article)
        try NotInterestedLog.record(article, in: context)
        try context.save()

        try ArticleQueueService().moveToQueue(article, in: context)

        #expect(article.state == .saved)
        #expect(!article.notInterested)
        let entries = try context.fetch(FetchDescriptor<NotInterestedEntry>())
        #expect(entries.isEmpty)
    }
}
