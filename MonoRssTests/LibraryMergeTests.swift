import Foundation
import SwiftData
import Testing
@testable import MonoRss

@MainActor
struct LibraryMergeTests {
    private func context() throws -> ModelContext {
        try InMemoryStore.makeContext()
    }

    @Test func snapshotOmitsArticlesWithoutURLAndKeepsCurrent() throws {
        let context = try context()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!, libraryUpdatedAt: Date(timeIntervalSince1970: 10))
        context.insert(feed)
        let current = Article(
            guid: "current",
            title: "Current",
            url: URL(string: "https://source.test/current"),
            state: .current,
            libraryUpdatedAt: Date(timeIntervalSince1970: 20),
            feed: feed
        )
        let orphan = Article(guid: "orphan", title: "No URL", state: .skipped, feed: feed)
        context.insert(current)
        context.insert(orphan)
        FolderStore.remember("Philosophy")

        let snapshot = try LibraryMerge.snapshot(from: context, now: Date(timeIntervalSince1970: 30))
        #expect(snapshot.feeds.map(\.feedURL) == ["https://source.test/rss"])
        #expect(snapshot.articles.map(\.key) == ["url:https://source.test/current"])
        #expect(snapshot.currentArticleKey == "url:https://source.test/current")
        #expect(snapshot.folderNames.contains("Philosophy"))
        FolderStore.remove("Philosophy")
    }

    @Test func newerSkipWinsOverOlderQueued() {
        let feed = LibraryFeed.stub(updatedAt: Date(timeIntervalSince1970: 5))
        let local = LibraryDocument(
            schemaVersion: 1,
            updatedAt: Date(timeIntervalSince1970: 10),
            folderNames: [],
            feeds: [feed],
            articles: [LibraryArticle.stub(state: .queued, updatedAt: Date(timeIntervalSince1970: 8))],
            tombstones: [],
            currentArticleKey: nil,
            currentUpdatedAt: nil
        )
        let remote = LibraryDocument(
            schemaVersion: 1,
            updatedAt: Date(timeIntervalSince1970: 12),
            folderNames: [],
            feeds: [feed],
            articles: [LibraryArticle.stub(state: .skipped, updatedAt: Date(timeIntervalSince1970: 11), completedAt: Date(timeIntervalSince1970: 11))],
            tombstones: [],
            currentArticleKey: nil,
            currentUpdatedAt: nil
        )

        let merged = LibraryMerge.merge(local: local, remote: remote, now: Date(timeIntervalSince1970: 13))
        #expect(merged.articles.count == 1)
        #expect(merged.articles[0].state == .skipped)
        #expect(merged.articles[0].updatedAt == Date(timeIntervalSince1970: 11))
    }

    @Test func olderRemoteDoesNotOverwriteNewerLocalState() {
        let feed = LibraryFeed.stub(updatedAt: Date(timeIntervalSince1970: 5))
        let local = LibraryDocument.empty(now: Date(timeIntervalSince1970: 20)).updating(
            feeds: [feed],
            articles: [LibraryArticle.stub(state: .saved, updatedAt: Date(timeIntervalSince1970: 18))]
        )
        let remote = LibraryDocument.empty(now: Date(timeIntervalSince1970: 19)).updating(
            feeds: [feed],
            articles: [LibraryArticle.stub(state: .queued, updatedAt: Date(timeIntervalSince1970: 4))]
        )

        let merged = LibraryMerge.merge(local: local, remote: remote, now: Date(timeIntervalSince1970: 21))
        #expect(merged.articles[0].state == .saved)
    }

    @Test func tombstoneRemovesFeedWhenItIsNewerThanLocalEdit() {
        let feed = LibraryFeed.stub(updatedAt: Date(timeIntervalSince1970: 5))
        let local = LibraryDocument.empty(now: Date(timeIntervalSince1970: 6)).updating(feeds: [feed])
        let remote = LibraryDocument.empty(now: Date(timeIntervalSince1970: 9)).updating(
            tombstones: [LibraryTombstone(feedURL: feed.feedURL, deletedAt: Date(timeIntervalSince1970: 8))]
        )

        let merged = LibraryMerge.merge(local: local, remote: remote, now: Date(timeIntervalSince1970: 10))
        #expect(merged.feeds.isEmpty)
        #expect(merged.tombstones.map(\.feedURL) == [feed.feedURL])
    }

    @Test func newerLocalFeedSurvivesOlderTombstone() {
        let feed = LibraryFeed.stub(title: "Edited", updatedAt: Date(timeIntervalSince1970: 20))
        let local = LibraryDocument.empty(now: Date(timeIntervalSince1970: 21)).updating(feeds: [feed])
        let remote = LibraryDocument.empty(now: Date(timeIntervalSince1970: 9)).updating(
            tombstones: [LibraryTombstone(feedURL: feed.feedURL, deletedAt: Date(timeIntervalSince1970: 8))]
        )

        let merged = LibraryMerge.merge(local: local, remote: remote, now: Date(timeIntervalSince1970: 22))
        #expect(merged.feeds.map(\.title) == ["Edited"])
        #expect(merged.tombstones.isEmpty)
    }

    @Test func unionKeepsFeedsFromBothSides() {
        let localFeed = LibraryFeed.stub(url: "https://a.test/rss", title: "A", updatedAt: Date(timeIntervalSince1970: 1))
        let remoteFeed = LibraryFeed.stub(url: "https://b.test/rss", title: "B", updatedAt: Date(timeIntervalSince1970: 2))
        let local = LibraryDocument.empty(now: Date(timeIntervalSince1970: 3)).updating(feeds: [localFeed])
        let remote = LibraryDocument.empty(now: Date(timeIntervalSince1970: 4)).updating(feeds: [remoteFeed])

        let merged = LibraryMerge.merge(local: local, remote: remote, now: Date(timeIntervalSince1970: 5))
        #expect(Set(merged.feeds.map(\.title)) == ["A", "B"])
    }

    @Test func emptyRemoteKeepsLocalSnapshot() throws {
        let context = try context()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!, folderName: "Security")
        context.insert(feed)
        let article = Article(
            guid: "one",
            title: "One",
            url: URL(string: "https://source.test/one"),
            state: .read,
            libraryUpdatedAt: Date(timeIntervalSince1970: 40),
            feed: feed
        )
        article.completedAt = Date(timeIntervalSince1970: 40)
        context.insert(article)

        let local = try LibraryMerge.snapshot(from: context, now: Date(timeIntervalSince1970: 50))
        let merged = LibraryMerge.merge(local: local, remote: .empty(now: Date(timeIntervalSince1970: 1)), now: Date(timeIntervalSince1970: 51))
        #expect(merged.feeds.count == 1)
        #expect(merged.articles.map(\.state) == [.read])
        #expect(merged.feeds[0].folderName == "Security")
    }

    @Test func articleIdentityUsesNormalizedURLNotGUID() {
        let feed = LibraryFeed.stub(updatedAt: Date(timeIntervalSince1970: 1))
        var localArticle = LibraryArticle.stub(state: .queued, updatedAt: Date(timeIntervalSince1970: 2), guid: "local-guid")
        localArticle.url = "https://source.test/story?utm_source=rss"
        localArticle.key = "url:https://source.test/story"
        var remoteArticle = LibraryArticle.stub(state: .skipped, updatedAt: Date(timeIntervalSince1970: 5), guid: "remote-guid")
        remoteArticle.url = "https://source.test/story"
        remoteArticle.key = "url:https://source.test/story"
        let local = LibraryDocument.empty(now: Date(timeIntervalSince1970: 3)).updating(feeds: [feed], articles: [localArticle])
        let remote = LibraryDocument.empty(now: Date(timeIntervalSince1970: 6)).updating(feeds: [feed], articles: [remoteArticle])

        let merged = LibraryMerge.merge(local: local, remote: remote, now: Date(timeIntervalSince1970: 7))
        #expect(merged.articles.count == 1)
        #expect(merged.articles[0].state == .skipped)
        #expect(merged.articles[0].guid == "remote-guid")
    }

    @Test func freshRSSOptionsSkipFeedInsertAndReadState() throws {
        let context = try context()
        let feed = Feed(title: "Local", feedURL: URL(string: "https://local.test/rss")!)
        context.insert(feed)
        let queued = Article(
            guid: "keep",
            title: "Keep",
            url: URL(string: "https://local.test/keep"),
            state: .queued,
            libraryUpdatedAt: Date(timeIntervalSince1970: 1),
            feed: feed
        )
        context.insert(queued)

        let remote = LibraryDocument.empty(now: Date(timeIntervalSince1970: 10)).updating(
            feeds: [
                LibraryFeed.stub(url: "https://local.test/rss", title: "Local", updatedAt: Date(timeIntervalSince1970: 9)),
                LibraryFeed.stub(url: "https://other.test/rss", title: "Other", updatedAt: Date(timeIntervalSince1970: 9))
            ],
            articles: [
                LibraryArticle.stub(
                    url: "https://local.test/keep",
                    state: .read,
                    updatedAt: Date(timeIntervalSince1970: 8),
                    guid: "keep",
                    feedURL: "https://local.test/rss"
                ),
                LibraryArticle.stub(
                    url: "https://local.test/skip",
                    state: .skipped,
                    updatedAt: Date(timeIntervalSince1970: 8),
                    guid: "skip",
                    feedURL: "https://local.test/rss",
                    completedAt: Date(timeIntervalSince1970: 8)
                )
            ]
        )

        try LibraryMerge.apply(remote, to: context, options: .forAccount(freshRSSEnabled: true))
        let feeds = try context.fetch(FetchDescriptor<Feed>())
        #expect(feeds.count == 1)
        #expect(queued.state == .queued)
        let skipped = try context.fetch(FetchDescriptor<Article>()).first { $0.guid == "skip" }
        #expect(skipped?.state == .skipped)
    }

    @Test func currentArticleLastWriteWins() {
        let feed = LibraryFeed.stub(updatedAt: Date(timeIntervalSince1970: 1))
        let first = LibraryArticle.stub(url: "https://source.test/one", state: .current, updatedAt: Date(timeIntervalSince1970: 3), guid: "one")
        let second = LibraryArticle.stub(url: "https://source.test/two", state: .current, updatedAt: Date(timeIntervalSince1970: 8), guid: "two")
        let local = LibraryDocument.empty(now: Date(timeIntervalSince1970: 4)).updating(
            feeds: [feed],
            articles: [first],
            currentArticleKey: first.key,
            currentUpdatedAt: Date(timeIntervalSince1970: 3)
        )
        let remote = LibraryDocument.empty(now: Date(timeIntervalSince1970: 9)).updating(
            feeds: [feed],
            articles: [second],
            currentArticleKey: second.key,
            currentUpdatedAt: Date(timeIntervalSince1970: 8)
        )

        let merged = LibraryMerge.merge(local: local, remote: remote, now: Date(timeIntervalSince1970: 10))
        #expect(merged.currentArticleKey == second.key)
        #expect(Set(merged.articles.map(\.guid)) == ["one", "two"])
    }

    @Test func applyUnionsExistingLibraryWithoutClobberingNewerLocal() throws {
        let context = try context()
        let feed = Feed(
            title: "Source",
            feedURL: URL(string: "https://source.test/rss")!,
            libraryUpdatedAt: Date(timeIntervalSince1970: 50)
        )
        context.insert(feed)
        let local = Article(
            guid: "story",
            title: "Story",
            url: URL(string: "https://source.test/story"),
            state: .saved,
            libraryUpdatedAt: Date(timeIntervalSince1970: 40),
            feed: feed
        )
        context.insert(local)

        let remote = LibraryDocument.empty(now: Date(timeIntervalSince1970: 12)).updating(
            feeds: [LibraryFeed.stub(title: "Older title", updatedAt: Date(timeIntervalSince1970: 5))],
            articles: [LibraryArticle.stub(state: .queued, updatedAt: Date(timeIntervalSince1970: 6))]
        )
        try LibraryMerge.apply(remote, to: context)
        #expect(feed.title == "Source")
        #expect(local.state == .saved)
    }

    @Test func jsonRoundTripThenApplyRestoresLibraryOntoEmptyStore() throws {
        let source = try context()
        let feed = Feed(
            title: "Trail of Bits",
            websiteURL: URL(string: "https://example.com"),
            feedURL: URL(string: "https://example.com/feed")!,
            folderName: "Security",
            libraryUpdatedAt: Date(timeIntervalSince1970: 20)
        )
        source.insert(feed)
        let saved = Article(
            guid: "saved",
            title: "Saved story",
            url: URL(string: "https://example.com/saved"),
            state: .saved,
            libraryUpdatedAt: Date(timeIntervalSince1970: 21),
            feed: feed
        )
        saved.completedAt = Date(timeIntervalSince1970: 21)
        source.insert(saved)
        let current = Article(
            guid: "current",
            title: "Current story",
            url: URL(string: "https://example.com/current"),
            state: .current,
            libraryUpdatedAt: Date(timeIntervalSince1970: 22),
            feed: feed
        )
        source.insert(current)

        let snapshot = try LibraryMerge.snapshot(from: source, now: Date(timeIntervalSince1970: 30))
        let data = try snapshot.encoded()
        let decoded = try LibraryDocument.decode(data)

        let destination = try context()
        try LibraryMerge.apply(decoded, to: destination)
        let restoredFeeds = try destination.fetch(FetchDescriptor<Feed>())
        #expect(restoredFeeds.map(\.title) == ["Trail of Bits"])
        #expect(restoredFeeds.first?.folderName == "Security")
        let restored = try destination.fetch(FetchDescriptor<Article>())
        #expect(Set(restored.map(\.state)) == [.saved, .current])
        #expect(restored.contains { $0.state == .current && $0.title == "Current story" })
        FolderStore.remove("Security")
    }
}

private extension LibraryDocument {
    func updating(
        feeds: [LibraryFeed]? = nil,
        articles: [LibraryArticle]? = nil,
        tombstones: [LibraryTombstone]? = nil,
        currentArticleKey: String? = nil,
        currentUpdatedAt: Date? = nil
    ) -> LibraryDocument {
        var copy = self
        if let feeds { copy.feeds = feeds }
        if let articles { copy.articles = articles }
        if let tombstones { copy.tombstones = tombstones }
        if currentArticleKey != nil || currentUpdatedAt != nil {
            copy.currentArticleKey = currentArticleKey ?? copy.currentArticleKey
            copy.currentUpdatedAt = currentUpdatedAt ?? copy.currentUpdatedAt
        }
        return copy
    }
}

private extension LibraryFeed {
    static func stub(
        url: String = "https://source.test/rss",
        title: String = "Source",
        updatedAt: Date
    ) -> LibraryFeed {
        LibraryFeed(
            feedURL: url,
            title: title,
            websiteURL: nil,
            folderName: nil,
            isEnabled: true,
            contentKind: "article",
            includeInToday: true,
            includeVideos: true,
            includeShorts: false,
            minVideoSeconds: 180,
            blockedWords: "",
            updatedAt: updatedAt
        )
    }
}

private extension LibraryArticle {
    static func stub(
        url: String = "https://source.test/story",
        state: ArticleState,
        updatedAt: Date,
        guid: String = "story",
        feedURL: String = "https://source.test/rss",
        completedAt: Date? = nil
    ) -> LibraryArticle {
        LibraryArticle(
            key: "url:\(url)",
            feedURL: feedURL,
            guid: guid,
            title: guid,
            url: url,
            state: state,
            completedAt: completedAt,
            isRemoteStarred: state == .saved,
            updatedAt: updatedAt
        )
    }
}
