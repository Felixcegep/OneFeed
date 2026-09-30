import Foundation
import SwiftData
import Testing
@testable import OneFeed

struct YouTubeChannelResolverTests {
    private let channelID = "UC2Y0KKomVw83JDgjVqVCGzg"

    @Test func acceptsBareAndAtPrefixedHandlesAndBuildsAtomFeedURL() async throws {
        for handle in ["MairedeLava", "@MairedeLava", "https://www.youtube.com/@MairedeLava"] {
            YouTubeChannelURLProtocol.setResponse(
                Data(#"{"channelId":"UC2Y0KKomVw83JDgjVqVCGzg"}"#.utf8),
                for: URL(string: "https://www.youtube.com/@MairedeLava")!
            )
            let resolved = try await YouTubeChannelResolver.resolve(handle, session: YouTubeChannelURLProtocol.session())
            #expect(resolved == "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelID)")
        }
    }

    @Test func channelIDURLDoesNotFetchChannelPage() async throws {
        let resolved = try await YouTubeChannelResolver.resolve("https://www.youtube.com/channel/\(channelID)")
        #expect(resolved == "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelID)")
        #expect(try await YouTubeChannelResolver.resolve("@\(channelID)") == resolved)
    }

    @Test func doesNotRewriteNonYouTubeURLsOrExistingFeedURLs() async throws {
        let website = "https://example.com/@MairedeLava"
        let feed = "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelID)"
        #expect(try await YouTubeChannelResolver.resolve(website) == website)
        #expect(try await YouTubeChannelResolver.resolve(feed) == feed)
    }

    @Test func extractsChannelIDFromBothHTMLMetadataForms() {
        #expect(YouTubeChannelResolver.channelID(in: #"<meta itemprop="channelId" content="UC2Y0KKomVw83JDgjVqVCGzg">"#) == channelID)
        #expect(YouTubeChannelResolver.channelID(in: #"{"channelId":"UC2Y0KKomVw83JDgjVqVCGzg"}"#) == channelID)
        #expect(YouTubeChannelResolver.channelID(in: #"{"externalId":"UC2Y0KKomVw83JDgjVqVCGzg"}"#) == channelID)
        #expect(YouTubeChannelResolver.channelID(in: #"{"browseId":"UC2Y0KKomVw83JDgjVqVCGzg"}"#) == channelID)
        #expect(YouTubeChannelResolver.channelID(in: "<html>no channel here</html>") == nil)
    }

    @Test func extractsYouTubeProfilePageIdentifierAndBuildsItsFeed() async throws {
        let realChannelID = "UC-mymmaz56Year8jGYSne_Q"
        let html = #"<meta itemprop="identifier" content="UC-mymmaz56Year8jGYSne_Q">"#
        #expect(YouTubeChannelResolver.channelID(in: html) == realChannelID)
        #expect(try await YouTubeChannelResolver.resolve("https://www.youtube.com/channel/\(realChannelID)")
            == "https://www.youtube.com/feeds/videos.xml?channel_id=\(realChannelID)")
    }

    @Test func rejectsMalformedHandleResolutionResponse() async {
        YouTubeChannelURLProtocol.setResponse(Data("<html>not a YouTube channel</html>".utf8), for: URL(string: "https://www.youtube.com/@Missing")!)
        do {
            _ = try await YouTubeChannelResolver.resolve("@Missing", session: YouTubeChannelURLProtocol.session())
            Issue.record("Expected malformed channel response to fail")
        } catch {
            #expect(error is FeedServiceError)
        }
    }

    @Test @MainActor func resolvedHandleCanBeAddedAndItsVideosAreImported() async throws {
        let channelURL = URL(string: "https://www.youtube.com/@MairedeLava")!
        let feedURL = URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelID)")!
        let atom = """
        <feed xmlns="http://www.w3.org/2005/Atom" xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns:media="http://search.yahoo.com/mrss/">
          <title>Maire de Laval</title>
          <entry><id>tag:youtube.com,2008:video:dQw4w9WgXcQ</id><yt:videoId>dQw4w9WgXcQ</yt:videoId><yt:channelId>\(channelID)</yt:channelId>
            <title>New video</title><link rel="alternate" href="https://www.youtube.com/watch?v=dQw4w9WgXcQ" />
            <published>2026-09-24T12:00:00Z</published><media:group><media:description>Video description</media:description></media:group>
          </entry>
        </feed>
        """
        YouTubeChannelURLProtocol.setResponse(Data(#"{"channelId":"\#(channelID)"}"#.utf8), for: channelURL)
        YouTubeChannelURLProtocol.setResponse(Data(atom.utf8), for: feedURL)
        let session = YouTubeChannelURLProtocol.session()
        let resolved = try await YouTubeChannelResolver.resolve("@MairedeLava", session: session)
        let context = ModelContext(try InMemoryStore.makeContainer())
        let service = FeedService(session: session, youtubeMetadata: YouTubeMetadataService(session: session))
        let feed = try await service.addSource(from: resolved, in: context)

        #expect(feed.feedURL == feedURL)
        #expect(feed.title == "Maire de Laval")
        let imported = try #require(try context.fetch(FetchDescriptor<Article>()).first)
        #expect(imported.title == "New video")
        #expect(imported.contentKind == "youtube")
        #expect(imported.videoID == "dQw4w9WgXcQ")
    }
}

private final class YouTubeChannelURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var responses: [URL: Data] = [:]

    static func setResponse(_ data: Data, for url: URL) {
        lock.lock()
        responses[url] = data
        lock.unlock()
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [YouTubeChannelURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "www.youtube.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        Self.lock.lock()
        let data = Self.responses[url]
        Self.lock.unlock()
        guard let data else { client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable)); return }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/html"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
