import Foundation
import SwiftData
import Testing
@testable import OneFeed

@MainActor
struct ArticleIdentityVideoTests {
    @Test func mergeDuplicatesCollapsesSameVideoAcrossDifferentURLs() throws {
        let context = try InMemoryStore.makeContext()
        let watchFeed = Feed(title: "Watch", feedURL: URL(string: "https://watch.test/rss")!)
        let shortFeed = Feed(title: "Short", feedURL: URL(string: "https://short.test/rss")!)
        context.insert(watchFeed)
        context.insert(shortFeed)
        context.insert(Article(
            guid: "watch-guid",
            title: "Watch",
            url: URL(string: "https://www.youtube.com/watch?v=abc123"),
            videoID: "abc123",
            feed: watchFeed
        ))
        context.insert(Article(
            guid: "short-guid",
            title: "Short",
            url: URL(string: "https://youtu.be/abc123"),
            videoID: "abc123",
            feed: shortFeed
        ))
        try context.save()

        _ = try ArticleIdentity.mergeDuplicates(in: context)

        #expect(try context.fetch(FetchDescriptor<Article>()).count == 1)
    }

    @Test func existingFindsTheFirstArticleByVideoIDWhenTheURLDiffers() {
        let first = Article(
            guid: "watch-guid",
            title: "Watch",
            url: URL(string: "https://www.youtube.com/watch?v=abc123"),
            videoID: "abc123"
        )
        let index = ArticleIdentityIndex(articles: [first])

        let found = index.existing(
            url: URL(string: "https://youtu.be/abc123"),
            guid: "short-guid",
            feedID: UUID(),
            videoID: "abc123"
        )

        #expect(found === first)
    }

    @Test func identityKeyUsesVideoID() {
        let article = Article(
            guid: "watch-guid",
            title: "Watch",
            url: URL(string: "https://www.youtube.com/watch?v=abc123"),
            videoID: "abc123"
        )

        #expect(ArticleIdentity.identityKey(for: article) == "video:abc123")
    }

    @Test func mergeKeepsTheLongerBodyWithoutReadingItOnTheOpenArticles() throws {
        let context = try InMemoryStore.makeContext()
        let url = URL(string: "https://source.test/story")!
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        context.insert(feed)
        let short = "<p>Short</p>"
        let long = "<p>\(String(repeating: "word ", count: 80))</p>"
        context.insert(Article(
            guid: "keeper",
            title: "Story",
            url: url,
            contentHTML: short,
            estimatedReadingMinutes: 30,
            feed: feed
        ))
        context.insert(Article(
            guid: "copy",
            title: "Story",
            url: url,
            contentHTML: long,
            estimatedReadingMinutes: 1
        ))
        try context.save()
        ArticleIdentity.liveHTMLReads = 0

        _ = try ArticleIdentity.mergeDuplicates(in: context)

        let remaining = try #require(context.fetch(FetchDescriptor<Article>()).first)
        #expect(remaining.contentHTML == long)
        #expect(remaining.estimatedReadingMinutes >= 2)
        #expect(ArticleIdentity.liveHTMLReads == 0)
    }
}
