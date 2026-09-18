import Foundation
import SwiftData

enum FeedServiceError: LocalizedError, Sendable {
    case invalidAddress
    case invalidResponse
    case http(Int)
    case discoveryFailed

    var errorDescription: String? {
        switch self {
        case .invalidAddress: "Enter a valid website or feed address."
        case .invalidResponse: "The source returned an unexpected response."
        case .http(let status): "The source could not be loaded (HTTP \(status))."
        case .discoveryFailed: "No RSS or Atom feed was advertised by this website."
        }
    }
}

/// The boundary consumed by feature ViewModels. Keeping ModelContext at this
/// boundary makes the SwiftData-backed implementation replaceable in tests
/// without leaking URLSession or parser details into a feature.
@MainActor
protocol FeedRepository: AnyObject {
    func addSource(from input: String, folderName: String?, in context: ModelContext) async throws -> Feed
    func refresh(_ feed: Feed, in context: ModelContext) async throws
    func refreshAll(in context: ModelContext, progress: RefreshProgress?) async throws
    func backfillYouTubeDurations(in context: ModelContext) async
}

extension FeedRepository {
    func addSource(from input: String, in context: ModelContext) async throws -> Feed {
        try await addSource(from: input, folderName: nil, in: context)
    }

    func refreshAll(in context: ModelContext) async throws {
        try await refreshAll(in: context, progress: nil)
    }

    func backfillYouTubeDurations(in context: ModelContext) async {}
}

@MainActor
final class FeedService {
    private let session: URLSession
    private let parser: FeedParser
    private let youtubeMetadata: YouTubeMetadataService

    init(
        session: URLSession = FeedService.makeSession(),
        parser: FeedParser = FeedParser(),
        youtubeMetadata: YouTubeMetadataService? = nil
    ) {
        self.session = session
        self.parser = parser
        self.youtubeMetadata = youtubeMetadata ?? YouTubeMetadataService(session: session)
    }

    private nonisolated static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 16
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: configuration)
    }

    func addSource(from input: String, folderName: String? = nil, in context: ModelContext) async throws -> Feed {
        guard let initialURL = Self.normalizedURL(from: input) else { throw FeedServiceError.invalidAddress }
        let (feedURL, parsed) = try await discoverAndParse(initialURL)
        let descriptor = FetchDescriptor<Feed>(predicate: #Predicate { $0.feedURL == feedURL })
        let normalizedFolder = folderName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = (normalizedFolder?.isEmpty == false) ? normalizedFolder : nil
        if let existing = try context.fetch(descriptor).first {
            if let folder, existing.folderName != folder {
                existing.folderName = folder
                existing.touchLibrary()
                FolderStore.remember(folder)
                try context.save()
                LibraryChange.noteStructureChanged()
            }
            return existing
        }

        let feed = Feed(
            title: parsed.title,
            websiteURL: parsed.websiteURL ?? initialURL,
            feedURL: feedURL,
            lastFetchedAt: .now,
            folderName: folder
        )
        context.insert(feed)
        if let folder { FolderStore.remember(folder) }
        try context.save()
        try await LibraryIngestActor(modelContainer: context.container).ingestParsedArticles(
            feedID: feed.id,
            articles: parsed.articles,
            youtubeMetadata: youtubeMetadata
        )
        LibraryChange.note(feed)
        return feed
    }

    func refresh(_ feed: Feed, in context: ModelContext) async throws {
        let feedID = feed.id
        let loaded = try await Self.download(
            RemoteFeedRequest(id: feed.id, url: feed.feedURL, etag: feed.etag, lastModified: feed.lastModified),
            session: session,
            parser: parser,
            timeout: 12
        )
        let actor = try SwiftDataIngest.actor(from: context)
        try await actor.applyDownload(feedID: feedID, loaded: loaded, youtubeMetadata: youtubeMetadata)
    }

    func refreshAll(in context: ModelContext, progress: RefreshProgress? = nil) async throws {
        let actor = try SwiftDataIngest.actor(from: context)
        try await actor.refreshLocalFeeds(
            session: session,
            parser: parser,
            youtubeMetadata: youtubeMetadata,
            progress: RefreshProgressSink(progress)
        )
    }

    struct RemoteFeedRequest: Sendable {
        let id: UUID
        let url: URL
        let etag: String?
        let lastModified: String?
    }

    enum LoadedFeed: Sendable {
        case notModified
        case updated(ParsedFeed, etag: String?, lastModified: String?)
    }

    struct FetchOutcome: Sendable {
        let id: UUID
        let loaded: LoadedFeed?
        let cancelled: Bool
        let transient: Bool
        let errorDescription: String?
    }

    struct FeedRefreshFailure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    static let maxConcurrentFetches = 4

    nonisolated static func download(
        _ request: RemoteFeedRequest,
        session: URLSession,
        parser: FeedParser,
        timeout: TimeInterval = 8
    ) async throws -> LoadedFeed {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: timeout)
        urlRequest.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) OneFeed/1.0",
            forHTTPHeaderField: "User-Agent"
        )
        urlRequest.setValue("application/atom+xml, application/rss+xml, application/xml, text/xml;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")
        if let etag = request.etag { urlRequest.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let modified = request.lastModified { urlRequest.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw FeedServiceError.invalidResponse }
        if http.statusCode == 304 { return .notModified }
        guard (200..<300).contains(http.statusCode) else { throw FeedServiceError.http(http.statusCode) }
        let parsed = try parser.parse(data)
        return .updated(
            parsed,
            etag: http.value(forHTTPHeaderField: "ETag"),
            lastModified: http.value(forHTTPHeaderField: "Last-Modified")
        )
    }

    private func discoverAndParse(_ url: URL) async throws -> (URL, ParsedFeed) {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw FeedServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw FeedServiceError.http(http.statusCode) }
        if let parsed = try? parser.parse(data) { return (http.url ?? url, parsed) }

        guard let html = String(data: data, encoding: .utf8),
              let discovered = Self.discoverFeedURL(in: html, relativeTo: http.url ?? url) else {
            throw FeedServiceError.discoveryFailed
        }
        let (feedData, feedResponse) = try await session.data(from: discovered)
        guard let feedHTTP = feedResponse as? HTTPURLResponse, (200..<300).contains(feedHTTP.statusCode) else {
            throw FeedServiceError.invalidResponse
        }
        return (feedHTTP.url ?? discovered, try parser.parse(feedData))
    }

    nonisolated static func filterEntry(from parsed: ParsedArticle) -> FilterEntry {
        FilterEntry(
            title: parsed.title,
            author: parsed.author ?? "",
            url: parsed.url?.absoluteString ?? "",
            content: [parsed.summary, parsed.contentHTML].compactMap { $0 }.joined(separator: " ")
        )
    }

    static let durationConcurrency = 2
    static let durationBackfillLimit = 8

    func backfillYouTubeDurations(in context: ModelContext) async {
        let actor = LibraryIngestActor(modelContainer: context.container)
        await actor.enrichMissingYouTubeDurations(limit: Self.durationBackfillLimit, youtubeMetadata: youtubeMetadata, persist: true)
    }

    nonisolated static func normalizedURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("feed:") || lower.hasPrefix("feeds:") || lower.hasPrefix("x-onefeed-feed:") {
            return URL(string: IncomingFeedURL.strippingFeedSchemes(trimmed))
        }
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        return URL(string: "https://\(trimmed)")
    }

    nonisolated static func discoverFeedURL(in html: String, relativeTo baseURL: URL) -> URL? {
        let pattern = #"<link[^>]+(?:type=[\"']application/(?:rss|atom)\+xml[\"'][^>]*href=[\"']([^\"']+)|href=[\"']([^\"']+)[\"'][^>]*type=[\"']application/(?:rss|atom)\+xml)[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) else { return nil }
        for index in 1..<match.numberOfRanges where match.range(at: index).location != NSNotFound {
            if let range = Range(match.range(at: index), in: html) {
                return URL(string: String(html[range]), relativeTo: baseURL)?.absoluteURL
            }
        }
        return nil
    }
}

extension FeedService: FeedRepository {}
