import Foundation
import SwiftData
import Testing
@testable import OneFeed

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

    @Test func feedParserReadsAtomFractionalSecondsAndPublished() throws {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Fractional</title>
          <entry>
            <id>tag:example.test,2026:frac</id>
            <title>With millis</title>
            <published>2026-09-04T00:00:00.000Z</published>
            <updated>2026-09-05T12:34:56.789Z</updated>
          </entry>
          <entry>
            <id>tag:example.test,2026:offset</id>
            <title>With offset</title>
            <updated>2026-06-12T09:19:34-05:00</updated>
          </entry>
          <entry>
            <id>tag:example.test,2026:naive</id>
            <title>No zone</title>
            <updated>2026-01-15T10:30:00</updated>
          </entry>
        </feed>
        """

        let parsed = try FeedParser().parse(Data(xml.utf8))
        #expect(parsed.articles.count == 3)

        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #expect(parsed.articles[0].publishedAt == frac.date(from: "2026-09-04T00:00:00.000Z"))
        #expect(parsed.articles[1].publishedAt == ISO8601DateFormatter().date(from: "2026-06-12T09:19:34-05:00"))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let naive = parsed.articles[2].publishedAt
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: naive)
        #expect(parts.year == 2026 && parts.month == 1 && parts.day == 15)
        #expect(parts.hour == 10 && parts.minute == 30 && parts.second == 0)
    }

    @Test func incomingFeedURLNormalizesFeedSchemesLikeNetNewsWire() {
        #expect(
            IncomingFeedURL.subscriptionAddress(from: URL(string: "feed:https://jvns.ca/atom.xml")!)
                == "https://jvns.ca/atom.xml"
        )
        #expect(
            IncomingFeedURL.subscriptionAddress(from: URL(string: "feed://example.com/rss")!)
                == "http://example.com/rss"
        )
        #expect(
            IncomingFeedURL.subscriptionAddress(from: URL(string: "feeds:example.com/atom.xml")!)
                == "https://example.com/atom.xml"
        )
        #expect(
            IncomingFeedURL.subscriptionAddress(from: URL(string: "x-onefeed-feed:https://vercel.com/atom")!)
                == "https://vercel.com/atom"
        )
        #expect(
            IncomingFeedURL.subscriptionAddress(from: URL(string: "onefeed://subscribe?url=https%3A%2F%2Fswift.org%2Fatom.xml")!)
                == "https://swift.org/atom.xml"
        )
        #expect(IncomingFeedURL.subscriptionAddress(from: URL(string: "onefeed://reader/abc")!) == nil)
        #expect(IncomingFeedURL.subscriptionAddress(from: URL(fileURLWithPath: "/tmp/book.epub")) == nil)
        #expect(IncomingFeedURL.subscriptionAddress(from: URL(fileURLWithPath: "/tmp/paper.pdf")) == nil)

        #expect(FeedService.normalizedURL(from: "feed:https://jvns.ca/atom.xml") == URL(string: "https://jvns.ca/atom.xml"))
        #expect(FeedService.normalizedURL(from: "example.com/feed") == URL(string: "https://example.com/feed"))
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
        // Seeded folders (Philosophy) sort ahead of unknown names (Development).
        #expect(groups.map(\.name) == ["Philosophy", "Development", "Unfiled"])
        #expect(groups[0].feeds.map(\.title) == ["Acephale", "CCK"])
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
        #expect(groups.map(\.name) == ["Philosophy", "Development"])
        #expect(groups[0].articles.map(\.title) == ["Essay"])
        #expect(groups[1].articles.map(\.title) == ["New", "Old"])
    }

    @Test @MainActor func feedInTwoFoldersAppearsInBothGroupsAndUnreadCounts() {
        let feed = Feed(title: "Aeon", feedURL: URL(string: "https://aeon.co/feed")!, folderName: "Philosophy")
        #expect(feed.addFolder("Must read"))
        let queued = Article(guid: "1", title: "Essay", publishedAt: .now, state: .queued, feed: feed)

        let groups = FeedFolderGrouping.groups(from: [feed])
        #expect(groups.map(\.name) == ["Must read", "Philosophy"])
        #expect(groups.allSatisfy { $0.feeds.map(\.title) == ["Aeon"] })

        let summaries = FeedFolderGrouping.folderSummaries(feeds: [feed], articles: [queued])
        #expect(summaries.map(\.name) == ["Must read", "Philosophy"])
        #expect(summaries.map(\.unreadCount) == [1, 1])
        #expect(summaries.map(\.feedCount) == [1, 1])
    }

    @Test @MainActor func removeFolderLeavesTheOtherLabel() {
        let feed = Feed(
            title: "Essay",
            feedURL: URL(string: "https://essay.test/rss")!,
            folderNames: ["Must read", "Philosophy"]
        )
        #expect(feed.removeFolder("Must read"))
        #expect(feed.memberships == ["Philosophy"])
        #expect(feed.folderName == "Philosophy")
        #expect(feed.removeFolder("Philosophy"))
        #expect(feed.memberships.isEmpty)
        #expect(feed.folderName == nil)
    }

    @Test @MainActor func applyRemotePrimaryFolderReplacesOnlyTheFirstLabel() {
        let moved = Feed(
            title: "Essay",
            feedURL: URL(string: "https://essay.test/rss")!,
            folderNames: ["Must read", "Programming"]
        )
        moved.applyRemotePrimaryFolder("Philosophy")
        #expect(moved.memberships == ["Philosophy", "Programming"])
        #expect(moved.folderName == "Philosophy")

        let unchanged = Feed(
            title: "Same",
            feedURL: URL(string: "https://same.test/rss")!,
            folderNames: ["Must read", "Programming"]
        )
        unchanged.applyRemotePrimaryFolder("Must read")
        #expect(unchanged.memberships == ["Must read", "Programming"])
        #expect(unchanged.folderName == "Must read")
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

    @Test func folderUnreadCountCollapsesSameStoryInsideOneFolder() {
        let development = Feed(title: "Swift", feedURL: URL(string: "https://c.test/rss")!, folderName: "Development")
        let other = Feed(title: "News", feedURL: URL(string: "https://n.test/rss")!, folderName: "Development")
        let newest = Article(guid: "1", title: "New", url: URL(string: "https://c.test/1"), publishedAt: .now, state: .queued, feed: development)
        let copy = Article(guid: "2", title: "Copy", url: URL(string: "https://n.test/2"), publishedAt: .now.addingTimeInterval(-30), state: .queued, feed: other)
        let cluster = UUID()
        let placements = [
            ArticleIdentity.identityKey(for: newest): StoryPlacement(relationshipRaw: ContentRelationship.sameStory.rawValue, storyClusterID: cluster),
            ArticleIdentity.identityKey(for: copy): StoryPlacement(relationshipRaw: ContentRelationship.sameStory.rawValue, storyClusterID: cluster),
        ]

        let summaries = FeedFolderGrouping.folderSummaries(feeds: [development, other], articles: [newest, copy], placements: placements)
        #expect(summaries.map(\.unreadCount) == [1])
    }

    @Test func feedRowsDropCopiesAndKeepASimilarCaption() {
        let feed = Feed(title: "Swift", feedURL: URL(string: "https://c.test/rss")!)
        let newest = Article(guid: "1", title: "New", url: URL(string: "https://c.test/1"), publishedAt: .now, state: .queued, feed: feed)
        let copy = Article(guid: "2", title: "Copy", url: URL(string: "https://c.test/2"), publishedAt: .now.addingTimeInterval(-30), state: .queued, feed: feed)
        let similar = Article(guid: "3", title: "Related", url: URL(string: "https://c.test/3"), publishedAt: .now.addingTimeInterval(-60), state: .queued, feed: feed)
        let cluster = UUID()
        let readAt = Date(timeIntervalSince1970: 1_700_000_000)
        let placements = [
            ArticleIdentity.identityKey(for: newest): StoryPlacement(relationshipRaw: ContentRelationship.sameStory.rawValue, storyClusterID: cluster),
            ArticleIdentity.identityKey(for: copy): StoryPlacement(relationshipRaw: ContentRelationship.sameStory.rawValue, storyClusterID: cluster),
            ArticleIdentity.identityKey(for: similar): StoryPlacement(relationshipRaw: ContentRelationship.related.rawValue, matchedConsumedAt: readAt),
        ]

        let rows = StoryGrouping.rows(from: [newest, copy, similar], placements: placements, expandedClusterIDs: [])
        #expect(rows.count == 3)
        guard case .article(let primary, _) = rows[0].kind else {
            Issue.record("Expected the newest story first")
            return
        }
        #expect(primary.title == "New")
        guard case .moreSources(_, let count) = rows[1].kind else {
            Issue.record("Expected the other source on its own row")
            return
        }
        #expect(count == 1)
        guard case .article(let related, let caption) = rows[2].kind else {
            Issue.record("Expected the related story to stay visible")
            return
        }
        #expect(related.title == "Related")
        #expect(caption?.hasPrefix("Similar to something you read") == true)
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

    @Test func parserDropsTrackingAndBlankImages() throws {
        let xml = """
        <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/"><channel><title>News</title>
        <item>
          <guid>blank-1</guid><title>No photo</title>
          <description><![CDATA[<p>Text only. <img src="https://cdn.example.test/spacer.gif"></p>]]></description>
        </item>
        <item>
          <guid>pixel-1</guid><title>Pixel</title>
          <media:thumbnail url="https://cdn.example.test/track/1x1.png"/>
          <description>Hello</description>
        </item>
        <item>
          <guid>photo-1</guid><title>Photo</title>
          <description><![CDATA[<p><img src="https://cdn.example.test/story.jpg"></p>]]></description>
        </item>
        </channel></rss>
        """
        let parsed = try FeedParser().parse(Data(xml.utf8))
        let blank = try #require(parsed.articles.first { $0.guid == "blank-1" })
        let pixel = try #require(parsed.articles.first { $0.guid == "pixel-1" })
        let photo = try #require(parsed.articles.first { $0.guid == "photo-1" })
        #expect(blank.imageURL == nil)
        #expect(pixel.imageURL == nil)
        #expect(photo.imageURL == URL(string: "https://cdn.example.test/story.jpg"))
        #expect(FeedImageURL.displayable(URL(string: "data:image/gif;base64,AAAA")) == nil)
    }

    @Test func parserReadsYouTubeAtomDuration() throws {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom" xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns:media="http://search.yahoo.com/mrss/">
          <title>Channel</title>
          <entry>
            <id>yt:video:dQw4w9WgXcQ</id>
            <title>Talk</title>
            <link rel="alternate" href="https://www.youtube.com/watch?v=dQw4w9WgXcQ"/>
            <media:group>
              <yt:duration seconds="1080"/>
            </media:group>
          </entry>
        </feed>
        """
        let parsed = try FeedParser().parse(Data(xml.utf8))
        let article = try #require(parsed.articles.first)
        #expect(article.durationSeconds == 1080)
        #expect(YouTubeProcessor.watchURL(for: "dQw4w9WgXcQ") == URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
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
        #expect(ContentClassifier.readingMinutes(words: 221) == 2)
        #expect(ContentClassifier.readingMinutes(words: 50) == 1)
        #expect(ContentClassifier.proseExcerpt("Article URL: https://dfarq.homeip.net/nec-v20") == nil)
        #expect(ContentClassifier.proseExcerpt("https://example.test/story") == nil)
        #expect(ContentClassifier.proseExcerpt("<p>A short claim about isolation.</p>") == "A short claim about isolation.")
        let lead = "<p>The opening claim stays on the card.</p>"
        let tail = String(repeating: "<p>later</p>", count: 20_000)
        #expect(ContentClassifier.proseExcerpt(lead + tail) == "The opening claim stays on the card.")
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
        let nested = """
        <html><script>var ytInitialPlayerResponse = {"videoDetails":{"lengthSeconds":"240","nested":{"a":1}},"streamingData":{}};</script></html>
        """
        #expect(YouTubeMetadataService.parseDuration(fromWatchHTML: nested) == 240)
        let bulky = String(repeating: "x", count: 80_000) + html
        #expect(YouTubeMetadataService.parseDuration(fromWatchHTML: bulky) == 1080)
        #expect(YouTubeMetadataService.parseDuration(fromWatchHTML: #""lengthSeconds": 1847"#) == 1847)
        #expect(YouTubeMetadataService.parseDuration(fromWatchHTML: #""approxDurationMs":"90000""#) == 90)
    }

    @Test func youtubeMetadataParsesPlayerJSON() throws {
        let data = #"{"videoDetails":{"lengthSeconds":"1847"}}"#.data(using: .utf8)!
        #expect(YouTubeMetadataService.parseDuration(fromPlayerJSON: data) == 1847)
        let adaptive = #"{"streamingData":{"adaptiveFormats":[{"approxDurationMs":"125000"}]}}"#.data(using: .utf8)!
        #expect(YouTubeMetadataService.parseDuration(fromPlayerJSON: adaptive) == 125)
    }

    @Test func youtubeProcessorParsesIDsAndThumbnail() {
        let watch = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
        #expect(YouTubeProcessor.parseVideoID(from: watch) == "dQw4w9WgXcQ")
        #expect(YouTubeProcessor.parseVideoID(fromGUID: "yt:video:dQw4w9WgXcQ") == "dQw4w9WgXcQ")
        #expect(YouTubeProcessor.thumbnailURL(for: "dQw4w9WgXcQ")?.absoluteString.contains("hqdefault.jpg") == true)
        #expect(YouTubeProcessor.isShort(url: URL(string: "https://www.youtube.com/shorts/abc12345678"), title: ""))
    }

    @Test @MainActor func shortQueuedVideoIsSkippedInsteadOfDeleted() throws {
        let context = try InMemoryStore.makeContext()
        let feed = Feed(
            title: "Channel",
            feedURL: URL(string: "https://youtube.test/rss")!,
            minVideoSeconds: 180
        )
        context.insert(feed)
        let queued = Article(
            guid: "short",
            title: "Clip",
            state: .queued,
            contentKind: "youtube",
            videoID: "dQw4w9WgXcQ",
            feed: feed
        )
        let current = Article(
            guid: "long",
            title: "Talk",
            state: .current,
            contentKind: "youtube",
            videoID: "abcdefghijk",
            feed: feed
        )
        let longEnough = Article(
            guid: "ok",
            title: "Lecture",
            state: .queued,
            contentKind: "youtube",
            videoID: "lmnopqrstuv",
            feed: feed
        )
        context.insert(queued)
        context.insert(current)
        context.insert(longEnough)

        #expect(YouTubeProcessor.applyFetchedDuration(90, to: queued))
        #expect(queued.state == .skipped)
        #expect(queued.durationSeconds == 90)
        #expect(try context.fetchCount(FetchDescriptor<Article>()) == 3)

        #expect(!YouTubeProcessor.applyFetchedDuration(90, to: current))
        #expect(current.state == .current)
        #expect(current.durationSeconds == 90)

        #expect(!YouTubeProcessor.applyFetchedDuration(600, to: longEnough))
        #expect(longEnough.state == .queued)
        #expect(longEnough.durationSeconds == 600)
    }

    @Test func videoDurationPhraseOmitsFakeOneMinute() {
        let unknown = Article(
            guid: "yt-unknown",
            title: "Talk",
            contentKind: "youtube",
            durationSeconds: 0,
            videoID: "dQw4w9WgXcQ"
        )
        #expect(unknown.kindLabel == "Video")
        #expect(unknown.timedDurationPhrase == nil)
        #expect(unknown.durationPhrase == "Video")

        let known = Article(
            guid: "yt-known",
            title: "Talk",
            estimatedReadingMinutes: 1,
            contentKind: "youtube",
            durationSeconds: 1847,
            videoID: "dQw4w9WgXcQ"
        )
        #expect(known.timedDurationPhrase == "31 min")
        #expect(known.durationPhrase == "31 min")
    }

    @Test func articleDurationPhraseOmitsTeaserOneMinuteAndHealsFromHTML() {
        let teaser = Article(
            guid: "short",
            title: "Brief",
            summary: "A short RSS blurb.",
            contentHTML: "<p>A short RSS blurb.</p>",
            estimatedReadingMinutes: 1
        )
        #expect(teaser.timedDurationPhrase == nil)
        #expect(teaser.durationPhrase.isEmpty)

        let extracted = Article(
            guid: "long",
            title: "Essay",
            contentHTML: "<p>" + String(repeating: "word ", count: 440) + "</p>",
            estimatedReadingMinutes: 1
        )
        extracted.refreshEstimatedReadingMinutes()
        #expect(extracted.estimatedReadingMinutes == 2)
        #expect(extracted.resolvedReadingMinutes == 2)
        #expect(extracted.timedDurationPhrase == "2 min read")

        let server = Article(
            guid: "fresh",
            title: "Essay",
            summary: "Teaser only.",
            estimatedReadingMinutes: 11
        )
        #expect(server.timedDurationPhrase == "11 min read")
    }

    @Test func articleRatingClampsAndClears() {
        let article = Article(guid: "rated", title: "Essay")
        article.setRating(8)
        #expect(article.rating == 5)
        article.setRating(3)
        #expect(article.rating == 3)
        article.setRating(0)
        #expect(article.rating == 0)
    }

    @Test func geminiClientParsesSummaryAndErrors() throws {
        let payload = #"{"candidates":[{"content":{"parts":[{"text":"A short summary."}]}}]}"#.data(using: .utf8)!
        #expect(try GeminiClient.parseSummary(from: payload) == "A short summary.")

        let error = #"{"error":{"message":"API key expired"}}"#.data(using: .utf8)!
        do {
            _ = try GeminiClient.parseSummary(from: error)
            Issue.record("Expected a Gemini API error")
        } catch let thrown as GeminiClientError {
            #expect(thrown == .api("API key expired"))
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test func displayExcerptPrefersAISummary() {
        let article = Article(
            guid: "1",
            title: "Talk",
            summary: "Feed blurb",
            contentKind: "youtube",
            aiSummary: "The video explains why 1/137 shows up in physics."
        )
        #expect(article.displayExcerpt == "The video explains why 1/137 shows up in physics.")
    }

    @Test func stripHTMLTurnsMarkupAndEntitiesIntoPlainPreviewText() {
        let aeon = #"<p><img src="https://images.aeonmedia.co/images/essay.jpg" alt="">More nothing now &amp; then</p>"#
        #expect(ContentClassifier.stripHTML(aeon) == "More nothing now & then")
        #expect(ContentClassifier.plainExcerpt(aeon).contains("<") == false)

        let truncated = #"<p><img src="https://images.aeonmedia.co/images/e2cbb509-e695-4191-8ab0-d8a48f630ec2/essay-gettyimages-225765"#
        #expect(ContentClassifier.stripHTML(truncated).isEmpty)
        #expect(Article(guid: "1", title: "More nothing now", summary: truncated).displayExcerpt == nil)

        let prose = #"<p>Nathan E. Sanders and I are writing a series of essays&nbsp;for <cite>The Renovator</cite>.</p>"#
        #expect(ContentClassifier.stripHTML(prose).contains("Nathan E. Sanders"))
        #expect(ContentClassifier.stripHTML(prose).contains("<") == false)
    }

    @Test func articleIdentityCollapsesSameURLAndPrefersANamedFeed() {
        let url = URL(string: "https://aeon.co/essays/more?utm_source=rss")!
        let aeon = Feed(title: "Aeon | a world of ideas", feedURL: URL(string: "https://aeon.co/feed")!)
        let orphan = Article(guid: "local", title: "More nothing now", url: url, state: .queued)
        let linked = Article(guid: "remote", title: "More nothing now", url: URL(string: "https://aeon.co/essays/more"), state: .queued, feed: aeon)

        let visible = FeedFolderGrouping.openArticles(from: [orphan, linked])
        #expect(visible.count == 1)
        #expect(visible.first?.feed?.title == "Aeon | a world of ideas")
        #expect(ArticleIdentity.normalizedURLString(url) == "https://aeon.co/essays/more")
    }

    @Test @MainActor func readerDocumentUsesEditorialTypeAndStripsScripts() {
        let article = Article(
            guid: "1",
            title: "Essay",
            contentHTML: "<p>Hello reader</p><script>alert(1)</script>"
        )
        let html = ReaderViewModel(article: article).documentHTML(fontChoice: .serif, textSize: .standard)
        #expect(html.contains("overflow-x: hidden"))
        #expect(html.contains("New York"))
        #expect(html.contains("1.55"))
        #expect(html.contains(OneFeedPalette.link.css))
        #expect(html.contains(OneFeedPalette.surface.css))
        #expect(html.contains(OneFeedPalette.attention.css))
        #expect(html.contains("Hello reader"))
        #expect(html.contains("onefeed-article"))
        #expect(!html.contains("alert(1)"))
    }

    @Test func videoSummaryBecomesArticleProse() {
        let html = ReaderHTML.videoSummaryBody(from: """
        The video explains why a cache helps.

        ## The hot path 02:10
        Keep the data the program touches often close to the processor.

        ## What to do 18:40
        Measure before adding another layer. A & B < C.
        """)
        #expect(html.contains("<p>The video explains why a cache helps.</p>"))
        #expect(html.contains("<h2>The hot path 02:10</h2>"))
        #expect(html.contains("<h2>What to do 18:40</h2>"))
        #expect(html.contains("A &amp; B &lt; C."))
        #expect(!html.contains("##"))
    }

    @Test @MainActor func youtubeSummaryUsesTheArticleReader() {
        let article = Article(
            guid: "yt",
            title: "Caches",
            contentKind: "youtube",
            aiSummary: """
            Opening thought.

            ## The point 01:00
            Details worth keeping.
            """
        )
        let html = ReaderViewModel(article: article).documentHTML(fontChoice: .serif, textSize: .standard)
        #expect(html.contains("New York"))
        #expect(html.contains("<h1>Caches</h1>"))
        #expect(html.contains("<h2>The point 01:00</h2>"))
        #expect(html.contains("Details worth keeping."))
        #expect(html.contains("onefeed-article"))
    }
}
