import Foundation
import SwiftData
import Testing
@testable import MonoRss

@MainActor
struct RetentionAndExtractionTests {
    private func context() throws -> ModelContext {
        try InMemoryStore.makeContext()
    }

    @Test func purgeKeepsSavedAndRecentArticles() throws {
        let context = try context()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        context.insert(feed)
        let old = Article(guid: "old", title: "Old", publishedAt: .now.addingTimeInterval(-10 * 86_400), state: .queued, feed: feed)
        let kept = Article(guid: "saved", title: "Saved", publishedAt: .now.addingTimeInterval(-10 * 86_400), state: .saved, feed: feed)
        let fresh = Article(guid: "fresh", title: "Fresh", publishedAt: .now, state: .queued, feed: feed)
        context.insert(old)
        context.insert(kept)
        context.insert(fresh)
        try context.save()

        let removed = try ArticleRetentionService().purge(in: context, olderThanDays: 7)
        #expect(removed == 1)
        let remaining = try context.fetch(FetchDescriptor<Article>(sortBy: [SortDescriptor(\.guid)]))
        #expect(remaining.map(\.guid) == ["fresh", "saved"])
    }

    @Test func purgeKeepsTodayDeckItemsAndHonorsForever() throws {
        let context = try context()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        context.insert(feed)
        let deckArticle = Article(guid: "deck", title: "Deck", publishedAt: .now.addingTimeInterval(-10 * 86_400), state: .current, feed: feed)
        let old = Article(guid: "old", title: "Old", publishedAt: .now.addingTimeInterval(-10 * 86_400), state: .queued, feed: feed)
        context.insert(deckArticle)
        context.insert(old)
        let deck = DailyDeck(dayStart: Calendar.current.startOfDay(for: .now))
        context.insert(deck)
        context.insert(DailyDeckItem(position: 1, status: .current, article: deckArticle, deck: deck))
        try context.save()

        #expect(try ArticleRetentionService().purge(in: context, olderThanDays: 0) == 0)
        let removed = try ArticleRetentionService().purge(in: context, olderThanDays: 7)
        #expect(removed == 1)
        let remaining = try context.fetch(FetchDescriptor<Article>(sortBy: [SortDescriptor(\.guid)]))
        #expect(remaining.map(\.guid) == ["deck"])
    }

    @Test func firstImportCutoffIsSevenDaysThenFollowsRetention() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let first = ArticleRetentionService.ingestCutoff(isFirstPopulate: true, now: now)
        #expect(first == now.addingTimeInterval(-7 * 86_400))
    }

    @Test func cancelledRefreshIsNotShownToTheUser() {
        #expect(RefreshFailure.message(for: CancellationError()) == nil)
        #expect(RefreshFailure.message(for: URLError(.cancelled)) == nil)
        #expect(RefreshFailure.message(for: URLError(.timedOut)) == nil)
        #expect(RefreshFailure.message(for: URLError(.cannotConnectToHost)) == nil)
        #expect(RefreshFailure.message(for: FeedServiceError.http(500)) == FeedServiceError.http(500).localizedDescription)
    }

    @Test func automaticExtractSkipsSubstantialRSS() {
        let policy = ArticleExtractionPolicy()
        let long = Array(repeating: "word", count: 90).joined(separator: " ")
        #expect(policy.shouldFetchPage(rssHTML: "<p>\(long)</p>", kind: "article") == false)
        #expect(policy.shouldFetchPage(rssHTML: "<p>Short</p>", kind: "article") == true)
        #expect(policy.shouldFetchPage(rssHTML: "<p>Short</p>", kind: "youtube") == false)
        var off = ArticleExtractionPolicy()
        off.mode = .off
        #expect(off.shouldFetchPage(rssHTML: "<p>Short</p>", kind: "article") == false)
    }

    @Test func swiftReadabilityExtractsArticleAndAbsoluteURLs() throws {
        let html = """
        <!doctype html><html><head><title>Site chrome</title></head>
        <body>
          <nav><a href="/home">Home</a><a href="/ads">Advertise</a></nav>
          <article>
            <h1>The real story</h1>
            <p>This paragraph is long enough that Readability should treat it as the article because it contains many words about the actual topic rather than navigation chrome or related links.</p>
            <p>A second paragraph continues the article with more substantial text so scoring prefers this region. <a href="/next">Continue</a></p>
            <img src="/photo.jpg" alt="photo">
          </article>
          <footer>Copyright subscribe newsletter</footer>
        </body></html>
        """
        let extracted = SwiftReadabilityExtractor().extract(
            fromHTML: html,
            pageURL: URL(string: "https://example.com/post")!
        )
        let content = try #require(extracted)
        #expect(content.contains("The real story") || content.contains("real story"))
        #expect(content.contains("https://example.com/photo.jpg"))
        #expect(content.contains("https://example.com/next"))
        #expect(!content.contains("Advertise"))
    }

    @Test func enrichUpcomingExtractsOnlyCurrentAndNextQueued() async throws {
        let context = try context()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        context.insert(feed)
        var articles: [Article] = []
        for index in 1...4 {
            let article = Article(
                guid: "g-\(index)",
                title: "Story \(index)",
                url: URL(string: "https://source.test/\(index)")!,
                publishedAt: .now.addingTimeInterval(Double(-index * 60)),
                summary: "Short",
                contentHTML: "<p>Short</p>",
                feed: feed
            )
            context.insert(article)
            articles.append(article)
        }
        let deck = DailyDeck(dayStart: Calendar.current.startOfDay(for: .now))
        context.insert(deck)
        for (index, article) in articles.enumerated() {
            context.insert(DailyDeckItem(
                position: index + 1,
                status: index == 0 ? .current : .queued,
                article: article,
                deck: deck
            ))
        }
        try context.save()

        let extractor = RecordingExtractor()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubExtractURLProtocol.self]
        StubExtractURLProtocol.body = "<html><body><p>Downloaded page with enough words to keep.</p></body></html>"
        let session = URLSession(configuration: config)
        let service = ArticleExtractionService(session: session, extractor: extractor)
        await service.enrichUpcoming(in: context, from: deck.items.first { $0.position == 1 }, extraQueued: 2)

        #expect(extractor.urls == [
            URL(string: "https://source.test/1")!,
            URL(string: "https://source.test/2")!,
            URL(string: "https://source.test/3")!,
        ])
        #expect(articles[0].contentHTML == "<p>Extracted https://source.test/1</p>")
        #expect(articles[3].contentHTML == "<p>Short</p>")
    }
}

private final class RecordingExtractor: ArticleExtracting, @unchecked Sendable {
    var urls: [URL] = []

    func extract(fromHTML html: String, pageURL: URL) -> String? {
        urls.append(pageURL)
        return "<p>Extracted \(pageURL.absoluteString)</p>"
    }
}

private final class StubExtractURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = "<html></html>"

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url ?? URL(string: "https://source.test/")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
