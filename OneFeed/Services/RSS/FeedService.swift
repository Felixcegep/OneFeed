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
    private let documentSession: URLSession
    private let documents: ImportedDocumentStore
    private let parser: FeedParser
    private let youtubeMetadata: YouTubeMetadataService

    init(
        session: URLSession = FeedService.makeSession(),
        parser: FeedParser = FeedParser(),
        youtubeMetadata: YouTubeMetadataService? = nil,
        documentSession: URLSession? = nil,
        documents: ImportedDocumentStore = .shared
    ) {
        self.session = session
        self.documentSession = documentSession ?? Self.makeDocumentSession()
        self.documents = documents
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

    private nonisolated static func makeDocumentSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 180
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    /// PDF and EPUB addresses are imported locally even when FreshRSS owns feed subscriptions.
    nonisolated static func importsWithoutRSS(_ input: String) -> Bool {
        guard let url = normalizedURL(from: input) else { return false }
        let scheme = url.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return false }
        return ImportedDocumentKind.infer(url: url) != nil
    }

    func addSource(from input: String, folderName: String? = nil, in context: ModelContext) async throws -> Feed {
        guard let initialURL = Self.normalizedURL(from: input) else { throw FeedServiceError.invalidAddress }
        if Self.importsWithoutRSS(input), let kind = ImportedDocumentKind.infer(url: initialURL) {
            let data = try await fetchDocument(initialURL)
            return try await addDocument(
                data: data,
                kind: kind,
                sourceURL: initialURL,
                folderName: folderName,
                in: context
            )
        }
        return try await addDiscovered(initialURL, folderName: folderName, in: context)
    }

    func refresh(_ feed: Feed, in context: ModelContext) async throws {
        guard feed.refreshesOverRSS else { return }
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

    private func addDiscovered(_ url: URL, folderName: String?, in context: ModelContext) async throws -> Feed {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw FeedServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw FeedServiceError.http(http.statusCode) }
        let responseURL = http.url ?? url
        let mime = http.value(forHTTPHeaderField: "Content-Type") ?? response.mimeType
        if let kind = Self.importedKind(data: data, mime: mime, url: responseURL)
            ?? Self.importedKind(data: data, mime: mime, url: url) {
            return try await addDocument(data: data, kind: kind, sourceURL: url, folderName: folderName, in: context)
        }

        let parser = self.parser
        do {
            let (feedURL, parsed) = try await Self.resolvedFeed(
                data: data,
                responseURL: responseURL,
                parser: parser,
                session: session
            )
            return try await insertSubscription(
                parsed: parsed,
                feedURL: feedURL,
                websiteFallback: url,
                folderName: folderName,
                in: context
            )
        } catch FeedServiceError.discoveryFailed {
            guard Self.isReadableHTMLPage(data) else { throw FeedServiceError.discoveryFailed }
            return try addPage(data: data, url: responseURL, folderName: folderName, in: context)
        }
    }

    private func addDocument(
        data: Data,
        kind: ImportedDocumentKind,
        sourceURL: URL,
        folderName: String?,
        in context: ModelContext
    ) async throws -> Feed {
        let article = try await ImportedDocumentService(store: documents, session: documentSession).importData(
            data,
            kind: kind,
            sourceURL: sourceURL,
            in: context,
            state: .queued,
            parkExisting: false
        )
        let feed = try upsertLocalFeed(
            url: sourceURL,
            title: article.title,
            websiteURL: sourceURL,
            folderName: folderName,
            contentKind: kind.rawValue,
            in: context
        )
        if article.feed == nil {
            article.feed = feed
        }
        feed.title = article.title
        feed.contentKind = kind.rawValue
        feed.websiteURL = sourceURL
        feed.lastFetchedAt = .now
        feed.touchLibrary()
        try context.save()
        LibraryChange.note(feed)
        return feed
    }

    private func addPage(data: Data, url: URL, folderName: String?, in context: ModelContext) throws -> Feed {
        let html = String(data: data.prefix(512_000), encoding: .utf8)
            ?? String(decoding: data.prefix(512_000), as: UTF8.self)
        let title = QueueLinkService.parseTitle(in: html) ?? QueueLinkService.fallbackTitle(for: url)
        let minutes = max(1, ContentClassifier.readingMinutes(words: ContentClassifier.wordCount(in: html)))
        let feed = try upsertLocalFeed(
            url: url,
            title: title,
            websiteURL: url,
            folderName: folderName,
            contentKind: "page",
            in: context
        )
        if let existing = existingArticle(url: url, in: context) {
            if existing.feed == nil { existing.feed = feed }
            try context.save()
            LibraryChange.note(feed)
            return feed
        }
        let article = Article(
            guid: url.absoluteString,
            title: title,
            url: url,
            publishedAt: .now,
            summary: ContentClassifier.plainExcerpt(html),
            contentHTML: html,
            estimatedReadingMinutes: minutes,
            state: .queued,
            contentKind: "article",
            imageURL: QueueLinkService.parseImage(in: html, relativeTo: url),
            libraryUpdatedAt: .now,
            feed: feed
        )
        context.insert(article)
        LibraryChange.note(article)
        try context.save()
        LibraryChange.note(feed)
        return feed
    }

    private func insertSubscription(
        parsed: ParsedFeed,
        feedURL: URL,
        websiteFallback: URL,
        folderName: String?,
        in context: ModelContext
    ) async throws -> Feed {
        let normalizedFolder = folderName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = (normalizedFolder?.isEmpty == false) ? normalizedFolder : nil
        let descriptor = FetchDescriptor<Feed>(predicate: #Predicate { $0.feedURL == feedURL })
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
            websiteURL: parsed.websiteURL ?? websiteFallback,
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

    private func upsertLocalFeed(
        url: URL,
        title: String,
        websiteURL: URL?,
        folderName: String?,
        contentKind: String,
        in context: ModelContext
    ) throws -> Feed {
        let normalizedFolder = folderName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = (normalizedFolder?.isEmpty == false) ? normalizedFolder : nil
        let descriptor = FetchDescriptor<Feed>(predicate: #Predicate { $0.feedURL == url })
        if let existing = try context.fetch(descriptor).first {
            if let folder, existing.folderName != folder {
                existing.folderName = folder
                existing.touchLibrary()
                FolderStore.remember(folder)
            }
            if !existing.refreshesOverRSS {
                existing.contentKind = contentKind
            }
            try context.save()
            return existing
        }
        let feed = Feed(
            title: title,
            websiteURL: websiteURL ?? url,
            feedURL: url,
            lastFetchedAt: .now,
            folderName: folder,
            contentKind: contentKind
        )
        context.insert(feed)
        if let folder { FolderStore.remember(folder) }
        try context.save()
        return feed
    }

    private func existingArticle(url: URL, in context: ModelContext) -> Article? {
        let key = ArticleIdentity.normalizedURLString(url)
        let articles = (try? context.fetch(FetchDescriptor<Article>())) ?? []
        return articles.first { ArticleIdentity.normalizedURLString($0.url) == key }
    }

    private func fetchDocument(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) OneFeed/1.0",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await documentSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FeedServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw FeedServiceError.http(http.statusCode) }
        guard data.count <= ImportedDocumentService.maxImportBytes else { throw ImportedDocumentError.tooLarge }
        return data
    }

    nonisolated static func importedKind(data: Data, mime: String?, url: URL) -> ImportedDocumentKind? {
        if let kind = ImportedDocumentKind.infer(url: url, mime: mime) { return kind }
        return ImportedDocumentKind.infer(magic: Data(data.prefix(8)))
    }

    /// A `<title>` inside an HTML page is not an RSS channel. Require a feed root, or at least one item.
    nonisolated static func looksLikeFeedDocument(_ data: Data) -> Bool {
        let sample = data.prefix(8_192)
        guard let text = String(data: sample, encoding: .utf8) ?? String(data: sample, encoding: .isoLatin1) else {
            return false
        }
        let lowered = text.lowercased()
        return lowered.contains("<rss")
            || lowered.contains("<feed")
            || lowered.contains("<channel")
            || lowered.contains("<rdf:rdf")
    }

    nonisolated static func isReadableHTMLPage(_ data: Data) -> Bool {
        let sample = data.prefix(4_096)
        guard let text = String(data: sample, encoding: .utf8) ?? String(data: sample, encoding: .isoLatin1) else {
            return false
        }
        let lowered = text.lowercased()
        if lowered.contains("<rss") || lowered.contains("<feed") { return false }
        return lowered.contains("<html")
            || lowered.contains("<!doctype html")
            || lowered.contains("<head")
            || lowered.contains("<body")
    }

    nonisolated private static func resolvedFeed(
        data: Data,
        responseURL: URL,
        parser: FeedParser,
        session: URLSession
    ) async throws -> (URL, ParsedFeed) {
        if let parsed = try? parser.parse(data),
           !parsed.articles.isEmpty || looksLikeFeedDocument(data) {
            return (responseURL, parsed)
        }

        guard let html = String(data: data, encoding: .utf8),
              let discovered = discoverFeedURL(in: html, relativeTo: responseURL) else {
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
