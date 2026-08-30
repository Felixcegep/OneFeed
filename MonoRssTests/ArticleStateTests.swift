import Foundation
import SwiftData
import Testing
@testable import MonoRss

@MainActor
struct ArticleStateTests {
    private func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: Feed.self, Article.self, SyncAccount.self, PendingSyncMutation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
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
}
