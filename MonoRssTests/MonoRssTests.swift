import Foundation
import SwiftData
import Testing
@testable import MonoRss

@MainActor
struct MonoRssTests {
    private func container() throws -> ModelContainer {
        try InMemoryStore.makeContainer()
    }

    @Test func selectorMaintainsExactlyOneCurrentAndRotatesSource() throws {
        let context = ModelContext(try container())
        let a = Feed(title: "A", feedURL: URL(string: "https://a.test/rss")!)
        let b = Feed(title: "B", feedURL: URL(string: "https://b.test/rss")!)
        context.insert(a); context.insert(b)
        let oldestA = Article(guid: "a1", title: "Old A", publishedAt: .now.addingTimeInterval(-300), feed: a)
        let newerB = Article(guid: "b1", title: "New B", publishedAt: .now.addingTimeInterval(-200), feed: b)
        context.insert(oldestA); context.insert(newerB)

        let service = ArticleQueueService()
        #expect(try service.ensureCurrent(in: context) === oldestA)
        #expect(try service.transition(oldestA, to: .read, in: context) === newerB)
        let current = ArticleState.current.rawValue
        #expect(try context.fetchCount(FetchDescriptor<Article>(predicate: #Predicate { $0.stateRawValue == current })) == 1)
    }

    @Test func savedStateStaysDistinct() throws {
        let context = ModelContext(try container())
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        let article = Article(guid: "one", title: "One", state: .current, feed: feed)
        context.insert(feed); context.insert(article)
        _ = try ArticleQueueService().transition(article, to: .saved, in: context)
        #expect(article.state == .saved)
        #expect(article.isRemoteStarred)
    }

    @Test func parserReadsRSSContentAndEstimatesTime() throws {
        let xml = """
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/"><channel><title>Example</title>
        <item><guid>1</guid><title>Story</title><link>https://example.test/story</link><content:encoded><![CDATA[<p>Hello reader</p>]]></content:encoded></item>
        </channel></rss>
        """
        let feed = try FeedParser().parse(Data(xml.utf8))
        #expect(feed.title == "Example")
        #expect(feed.articles.first?.contentHTML == "<p>Hello reader</p>")
        #expect(feed.articles.first?.estimatedReadingMinutes == 1)
    }

    @Test func feedDiscoveryResolvesRelativeURL() {
        let html = #"<html><head><link rel="alternate" type="application/rss+xml" href="/feed.xml"></head></html>"#
        #expect(FeedService.discoverFeedURL(in: html, relativeTo: URL(string: "https://example.test/blog")!) == URL(string: "https://example.test/feed.xml"))
    }

    @Test func feedServiceSkipsShortYouTubeAndBlockedWords() async throws {
        let context = ModelContext(try container())
        let xml = """
        <rss version="2.0"><channel><title>YT</title>
        <item><guid>s1</guid><title>Short clip</title><link>https://www.youtube.com/shorts/abc12345678</link></item>
        <item><guid>a1</guid><title>Nice essay</title><link>https://example.test/one</link><description>hello world</description></item>
        <item><guid>a2</guid><title>spam headline</title><link>https://example.test/two</link><description>body</description></item>
        </channel></rss>
        """
        let feedURL = URL(string: "https://yt.test/rss")!
        let feed = Feed(
            title: "YT",
            feedURL: feedURL,
            includeShorts: false,
            blockedWords: "spam"
        )
        context.insert(feed)

        StubFeedURLProtocol.response = (
            Data(xml.utf8),
            HTTPURLResponse(url: feedURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubFeedURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = FeedService(session: session, parser: FeedParser(), youtubeMetadata: YouTubeMetadataService())
        try await service.refresh(feed, in: context)

        let titles = Set(try context.fetch(FetchDescriptor<Article>()).map(\.title))
        #expect(titles.contains("Nice essay"))
        #expect(!titles.contains("Short clip"))
        #expect(!titles.contains("spam headline"))
    }
}

private final class StubFeedURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var response: (Data, URLResponse)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let client, let response = Self.response else { return }
        client.urlProtocol(self, didReceive: response.1, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: response.0)
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
