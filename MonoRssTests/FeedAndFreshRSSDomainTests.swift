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

    @Test func folderSummariesIncludeEmptyFoldersAndUnreadCounts() {
        let development = Feed(title: "Swift", feedURL: URL(string: "https://c.test/rss")!, folderName: "Development")
        let empty = Feed(title: "Quiet", feedURL: URL(string: "https://e.test/rss")!, folderName: "Quiet")
        let unread = Article(guid: "1", title: "New", publishedAt: .now, state: .queued, feed: development)
        let read = Article(guid: "2", title: "Old", publishedAt: .now, state: .read, feed: empty)

        let summaries = FeedFolderGrouping.folderSummaries(feeds: [development, empty], articles: [unread, read])
        #expect(summaries.map(\.name) == ["Development", "Quiet"])
        #expect(summaries[0].unreadCount == 1)
        #expect(summaries[1].unreadCount == 0)
    }

    @Test func parserReadsEnclosureAndYouTubeItem() throws {
        let xml = """
        <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:media="http://search.yahoo.com/mrss/"><channel><title>Media</title>
        <item>
          <guid>pod-1</guid><title>Episode</title>
          <enclosure url="https://cdn.example.test/ep.mp3" type="audio/mpeg" length="12345"/>
          <itunes:duration>12:30</itunes:duration>
          <media:thumbnail url="https://cdn.example.test/cover.jpg"/>
          <description>Podcast notes</description>
        </item>
        <item>
          <guid>yt-1</guid><title>Talk</title>
          <link>https://www.youtube.com/watch?v=dQw4w9WgXcQ</link>
        </item>
        </channel></rss>
        """

        let parsed = try FeedParser().parse(Data(xml.utf8))
        let podcast = try #require(parsed.articles.first { $0.guid == "pod-1" })
        let youtube = try #require(parsed.articles.first { $0.guid == "yt-1" })

        #expect(podcast.enclosureURL == URL(string: "https://cdn.example.test/ep.mp3"))
        #expect(podcast.enclosureMIME == "audio/mpeg")
        #expect(podcast.durationSeconds == 750)
        #expect(podcast.imageURL == URL(string: "https://cdn.example.test/cover.jpg"))
        #expect(youtube.url == URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
    }

    @Test func contentClassifierDetectsYouTubePodcastAndArticle() {
        let youtube = ContentClassifier.classify(
            url: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"),
            title: "Talk",
            summary: nil,
            contentHTML: nil,
            enclosureMIME: nil,
            durationSeconds: 600
        )
        #expect(youtube.kind == .youtube)
        #expect(youtube.videoID == "dQw4w9WgXcQ")
        #expect(youtube.estimatedMinutes == 10)

        let podcast = ContentClassifier.classify(
            url: URL(string: "https://example.test/ep"),
            title: "Episode",
            summary: "notes",
            contentHTML: nil,
            enclosureMIME: "audio/mpeg",
            durationSeconds: 3600
        )
        #expect(podcast.kind == .podcast)
        #expect(podcast.estimatedMinutes == 60)

        let article = ContentClassifier.classify(
            url: URL(string: "https://example.test/post"),
            title: "Essay",
            summary: nil,
            contentHTML: "<p>" + String(repeating: "word ", count: 440) + "</p>",
            enclosureMIME: nil,
            durationSeconds: nil
        )
        #expect(article.kind == .article)
        #expect(article.estimatedMinutes == 2)
    }

    @Test func skipShortYouTubeDetectsShortsPathAndHashTag() {
        #expect(
            ContentClassifier.skipShortYouTube(
                url: URL(string: "https://www.youtube.com/shorts/abc12345678"),
                title: "Clip",
                durationSeconds: nil
            )
        )
        #expect(
            ContentClassifier.skipShortYouTube(
                url: URL(string: "https://www.youtube.com/watch?v=abc12345678"),
                title: "Fun #shorts",
                durationSeconds: nil
            )
        )
        #expect(
            ContentClassifier.skipShortYouTube(
                url: URL(string: "https://www.youtube.com/watch?v=abc12345678"),
                title: "Long talk",
                durationSeconds: 120
            )
        )
        #expect(
            !ContentClassifier.skipShortYouTube(
                url: URL(string: "https://www.youtube.com/watch?v=abc12345678"),
                title: "Long talk",
                durationSeconds: 600
            )
        )
    }

    @Test func filterEngineAppliesKeepDropStarAndBlockedWords() {
        let entry = FilterEntry(title: "Swift concurrency", author: "Ada", url: "https://a.test", content: "actors and tasks")
        let feed = FilterFeedContext(title: "Dev", url: "https://dev.test/rss")

        let keepOnly = FilterEngine.apply(
            rules: [FilterRule(action: .keep, field: .title, pattern: "Swift")],
            entry: entry,
            feed: feed
        )
        #expect(!keepOnly.drop)

        let keepMiss = FilterEngine.apply(
            rules: [FilterRule(action: .keep, field: .title, pattern: "Rust")],
            entry: entry,
            feed: feed
        )
        #expect(keepMiss.drop)

        let drop = FilterEngine.apply(
            rules: [FilterRule(action: .drop, field: .content, pattern: "tasks")],
            entry: entry,
            feed: feed
        )
        #expect(drop.drop)
        #expect(!drop.star)

        let starred = FilterEngine.apply(
            rules: [FilterRule(action: .star, field: .author, pattern: "Ada")],
            entry: entry,
            feed: feed
        )
        #expect(starred.star)

        let blocked = FilterEngine.apply(
            rules: FilterEngine.blockedWordRules(from: "concurrency\nspam"),
            entry: entry,
            feed: feed
        )
        #expect(blocked.drop)
    }

    @Test func youtubeMetadataParsesWatchHTML() {
        let html = """
        <html><script>var ytInitialPlayerResponse = {"videoDetails":{"lengthSeconds":"1080"}};</script>
        <meta itemprop="duration" content="PT18M" /></html>
        """
        #expect(YouTubeMetadataService.parseDuration(fromWatchHTML: html) == 1080)
    }

    @Test func youtubeProcessorParsesIDsAndThumbnail() {
        let watch = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
        #expect(YouTubeProcessor.parseVideoID(from: watch) == "dQw4w9WgXcQ")
        #expect(YouTubeProcessor.thumbnailURL(for: "dQw4w9WgXcQ")?.absoluteString.contains("hqdefault.jpg") == true)
        #expect(YouTubeProcessor.isShort(url: URL(string: "https://www.youtube.com/shorts/abc12345678"), title: ""))
    }
}
