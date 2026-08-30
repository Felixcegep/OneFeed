import Foundation
import Testing
@testable import MonoRss

struct FeedAndFreshRSSDomainTests {
    @Test func feedParserReadsAtomContentAndTimestamp() throws {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Atom Source</title><link href="https://example.test/" />
          <entry><id>tag:example.test,2026:1</id><title>Atom story</title>
            <link rel="alternate" href="https://example.test/story" />
            <updated>2026-08-29T12:00:00Z</updated><content type="html">&lt;p&gt;Body&lt;/p&gt;</content>
          </entry>
        </feed>
        """

        let parsed = try FeedParser().parse(Data(xml.utf8))
        let article = try #require(parsed.articles.first)
        #expect(parsed.title == "Atom Source")
        #expect(article.guid == "tag:example.test,2026:1")
        #expect(article.url == URL(string: "https://example.test/story"))
        #expect(article.contentHTML == "<p>Body</p>")
        #expect(article.publishedAt == ISO8601DateFormatter().date(from: "2026-08-29T12:00:00Z"))
    }

    @Test func freshRSSConfigurationAcceptsHTTPAndHTTPS() throws {
        let secure = try FreshRSSConfiguration(
            baseURL: URL(string: "https://rss.example.test/freshrss/")!,
            username: "reader"
        )
        #expect(secure.baseURL.absoluteString == "https://rss.example.test/freshrss")
        #expect(secure.endpoint("api/greader.php").absoluteString == "https://rss.example.test/freshrss/api/greader.php")

        let local = try FreshRSSConfiguration(
            baseURL: URL(string: "http://localhost/freshrss")!,
            username: "reader"
        )
        #expect(local.baseURL.absoluteString == "http://localhost/freshrss")
        #expect(FreshRSSConfiguration.normalizedServerURL(from: "192.168.1.12:8080") == URL(string: "http://192.168.1.12:8080"))
    }

    @Test func freshRSSItemSupportsStringAuthorAndMillisecondTimestamp() throws {
        let payload = #"{"id":"item-1","title":"Story","author":"A Reader","crawlTimeMsec":"1760000000123","summary":{"content":"Excerpt"},"categories":[]}"#.data(using: .utf8)!
        let item = try JSONDecoder().decode(FreshRSSItem.self, from: payload)
        #expect(item.author?.name == "A Reader")
        #expect(item.preferredHTML == "Excerpt")
        #expect(item.publishedAt == Date(timeIntervalSince1970: 1760000000.123))
        #expect(item.snapshot.isRead == false)
        #expect(item.snapshot.isStarred == false)
    }
}
