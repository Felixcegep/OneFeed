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

        let pastedAPI = try FreshRSSConfiguration(
            baseURL: URL(string: "http://100.65.245.62:8081/api/greader.php")!,
            username: "felix"
        )
        #expect(pastedAPI.baseURL.absoluteString == "http://100.65.245.62:8081")
        #expect(
            pastedAPI.endpoint("api/greader.php/accounts/ClientLogin").absoluteString
                == "http://100.65.245.62:8081/api/greader.php/accounts/ClientLogin"
        )

        let pastedLogin = try FreshRSSConfiguration(
            baseURL: URL(string: "http://100.65.245.62:8081/api/greader.php/accounts/ClientLogin")!,
            username: "felix"
        )
        #expect(pastedLogin.baseURL.absoluteString == "http://100.65.245.62:8081")
        #expect(
            pastedLogin.endpoint("api/greader.php/accounts/ClientLogin").absoluteString.hasSuffix("/")
                == false
        )

        let trimmed = try FreshRSSCredentials(username: " felix ", password: " 12345 ")
        #expect(trimmed.username == "felix")
        #expect(trimmed.password == "12345")
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

    @Test func subscriptionDecodesGReaderFolderCategories() throws {
        let payload = #"{"id":"feed/2","title":"1000-Word Philosophy","url":"https://1000wordphilosophy.com/feed/","htmlUrl":"https://1000wordphilosophy.com","categories":[{"id":"user/-/label/Philosophy","label":"Philosophy"}]}"#.data(using: .utf8)!
        let subscription = try JSONDecoder().decode(FreshRSSSubscription.self, from: payload)
        #expect(subscription.folderName == "Philosophy")
        #expect(subscription.resolvedFeedURL == URL(string: "https://1000wordphilosophy.com/feed/"))
    }

    @Test func feedFolderGroupingSortsNamedFoldersAndKeepsUnfiledLast() {
        let philosophy = Feed(title: "Acephale", feedURL: URL(string: "https://a.test/rss")!, folderName: "Philosophy")
        let unfiled = Feed(title: "Ars", feedURL: URL(string: "https://b.test/rss")!)
        let development = Feed(title: "Swift", feedURL: URL(string: "https://c.test/rss")!, folderName: "Development")
        let alsoPhilosophy = Feed(title: "CCK", feedURL: URL(string: "https://d.test/rss")!, folderName: "Philosophy")

        let groups = FeedFolderGrouping.groups(from: [philosophy, unfiled, development, alsoPhilosophy])
        #expect(groups.map(\.name) == ["Development", "Philosophy", "Unfiled"])
        #expect(groups[1].feeds.map(\.title) == ["Acephale", "CCK"])
        #expect(groups[2].feeds.map(\.title) == ["Ars"])
    }

    @Test func folderArticleGroupsKeepNewestUnreadCardsPerFolder() {
        let development = Feed(title: "Swift", feedURL: URL(string: "https://c.test/rss")!, folderName: "Development")
        let philosophy = Feed(title: "Acephale", feedURL: URL(string: "https://a.test/rss")!, folderName: "Philosophy")
        let newest = Article(guid: "1", title: "New", publishedAt: .now, state: .queued, feed: development)
        let older = Article(guid: "2", title: "Old", publishedAt: .now.addingTimeInterval(-60), state: .current, feed: development)
        let other = Article(guid: "3", title: "Essay", publishedAt: .now.addingTimeInterval(-10), state: .queued, feed: philosophy)
        let done = Article(guid: "4", title: "Done", publishedAt: .now, state: .read, feed: philosophy)

        let groups = FeedFolderGrouping.folderArticleGroups(from: [newest, older, other, done])
        #expect(groups.map(\.name) == ["Development", "Philosophy"])
        #expect(groups[0].articles.map(\.title) == ["New", "Old"])
        #expect(groups[1].articles.map(\.title) == ["Essay"])
    }
}
