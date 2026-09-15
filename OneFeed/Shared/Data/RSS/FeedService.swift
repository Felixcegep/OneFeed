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
        var index = ArticleIdentityIndex(articles: identityArticles(in: context))
        _ = try await insert(parsed.articles, into: feed, in: context, index: &index, fetchDurations: false)
        await enrichMissingYouTubeDurations(in: context)
        try context.save()
        LibraryChange.note(feed)
        return feed
    }

    func refresh(_ feed: Feed, in context: ModelContext) async throws {
        let loaded = try await Self.download(
            RemoteFeedRequest(id: feed.id, url: feed.feedURL, etag: feed.etag, lastModified: feed.lastModified),
            session: session,
            parser: parser,
            timeout: 12
        )
        var index = ArticleIdentityIndex(articles: identityArticles(in: context))
        _ = try await apply(loaded, to: feed, in: context, index: &index)
    }

    func refreshAll(in context: ModelContext, progress: RefreshProgress? = nil) async throws {
        let feeds = try context.fetch(FetchDescriptor<Feed>(predicate: #Predicate { $0.isEnabled && $0.remoteID == nil }))
        progress?.begin(phase: .sources, total: feeds.count)
        let requests = feeds.map { RemoteFeedRequest(id: $0.id, url: $0.feedURL, etag: $0.etag, lastModified: $0.lastModified) }
        let feedsByID = Dictionary(uniqueKeysWithValues: feeds.map { ($0.id, $0) })
        var identityIndex = ArticleIdentityIndex(articles: identityArticles(in: context))
        var succeeded = 0
        var insertedCount = 0
        var firstError: Error?
        let session = self.session
        let parser = self.parser
        var unsaved = 0
        await withTaskGroup(of: FetchOutcome.self) { group in
            var next = 0
            func startOne() {
                guard next < requests.count else { return }
                let request = requests[next]
                next += 1
                group.addTask {
                    do {
                        let loaded = try await Self.download(request, session: session, parser: parser)
                        return FetchOutcome(id: request.id, loaded: loaded, cancelled: false, transient: false, errorDescription: nil)
                    } catch {
                        return FetchOutcome(
                            id: request.id,
                            loaded: nil,
                            cancelled: error.isCancellation,
                            transient: error.isTransientNetwork,
                            errorDescription: error.localizedDescription
                        )
                    }
                }
            }
            for _ in 0..<min(Self.maxConcurrentFetches, requests.count) {
                startOne()
            }
            for await outcome in group {
                startOne()
                guard let feed = feedsByID[outcome.id] else { continue }
                progress?.startItem(title: feed.title)
                do {
                    if Task.isCancelled {
                        group.cancelAll()
                        firstError = firstError ?? CancellationError()
                        progress?.finishItem(newArticles: 0)
                        continue
                    }
                    if let loaded = outcome.loaded {
                        let added = try await apply(
                            loaded,
                            to: feed,
                            in: context,
                            persist: false,
                            fetchDurations: false,
                            index: &identityIndex
                        )
                        insertedCount += added
                        unsaved += 1
                        if unsaved >= 6 {
                            try context.save()
                            unsaved = 0
                        }
                        succeeded += 1
                        progress?.finishItem(newArticles: added)
                    } else {
                        feed.lastFetchedAt = .now
                        unsaved += 1
                        if outcome.cancelled {
                            group.cancelAll()
                            firstError = firstError ?? CancellationError()
                        } else if !outcome.transient {
                            firstError = firstError ?? FeedRefreshFailure(outcome.errorDescription ?? "The source returned an unexpected response.")
                        }
                        progress?.finishItem(newArticles: 0)
                    }
                } catch {
                    feed.lastFetchedAt = .now
                    unsaved += 1
                    if error.isCancellation {
                        group.cancelAll()
                        firstError = firstError ?? error
                    } else if !error.isTransientNetwork {
                        firstError = firstError ?? error
                    }
                    progress?.finishItem(newArticles: 0)
                }
            }
        }
        if unsaved > 0 { try? context.save() }
        await enrichMissingYouTubeDurations(in: context)
        if insertedCount > 0 {
            _ = try? ArticleIdentity.mergeDuplicates(in: context)
        }
        if succeeded == 0, let firstError { throw firstError }
    }

    private struct RemoteFeedRequest: Sendable {
        let id: UUID
        let url: URL
        let etag: String?
        let lastModified: String?
    }

    private enum LoadedFeed: Sendable {
        case notModified
        case updated(ParsedFeed, etag: String?, lastModified: String?)
    }

    private struct FetchOutcome: Sendable {
        let id: UUID
        let loaded: LoadedFeed?
        let cancelled: Bool
        let transient: Bool
        let errorDescription: String?
    }

    private struct FeedRefreshFailure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    private static let maxConcurrentFetches = 4

    private nonisolated static func download(
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

    @discardableResult
    private func apply(
        _ loaded: LoadedFeed,
        to feed: Feed,
        in context: ModelContext,
        persist: Bool = true,
        fetchDurations: Bool = false,
        index: inout ArticleIdentityIndex
    ) async throws -> Int {
        var inserted = 0
        switch loaded {
        case .notModified:
            feed.lastFetchedAt = .now
        case .updated(let parsed, let etag, let lastModified):
            feed.title = parsed.title
            feed.websiteURL = parsed.websiteURL ?? feed.websiteURL
            feed.etag = etag
            feed.lastModified = lastModified
            feed.lastFetchedAt = .now
            inserted = try await insert(
                parsed.articles,
                into: feed,
                in: context,
                index: &index,
                fetchDurations: fetchDurations
            )
        }
        if persist {
            await enrichMissingYouTubeDurations(in: context)
            try context.save()
        }
        return inserted
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

    @discardableResult
    private func insert(
        _ parsedArticles: [ParsedArticle],
        into feed: Feed,
        in context: ModelContext,
        index: inout ArticleIdentityIndex,
        fetchDurations: Bool = false
    ) async throws -> Int {
        let feedKind = ContentKind(rawValue: feed.contentKind) ?? .article
        let filterRules = FilterEngine.blockedWordRules(from: feed.blockedWords)
        let feedContext = FilterFeedContext(title: feed.title, url: feed.feedURL.absoluteString)
        var inserted = 0

        let cutoff = ArticleRetentionService.ingestCutoff(isFirstPopulate: isEmptyFeed(feed, in: context))
        for parsed in parsedArticles {
            if let existing = index.existing(url: parsed.url, guid: parsed.guid, feedID: feed.id) {
                if existing.feed == nil { existing.feed = feed }
                continue
            }
            if let cutoff, parsed.publishedAt < cutoff { continue }
            let classified = ContentClassifier.classify(
                url: parsed.url,
                title: parsed.title,
                summary: parsed.summary,
                contentHTML: parsed.contentHTML,
                enclosureMIME: parsed.enclosureMIME,
                durationSeconds: parsed.durationSeconds,
                feedType: feedKind
            )

            if classified.kind == .youtube {
                if classified.isShort, !feed.includeShorts { continue }
                if !feed.includeVideos { continue }

                let videoID = classified.videoID ?? YouTubeProcessor.parseVideoID(fromGUID: parsed.guid)
                var duration = classified.durationSeconds
                if fetchDurations, !classified.isShort, duration == nil, let videoID {
                    duration = await youtubeMetadata.fetchDuration(videoID: videoID)
                }
                if !YouTubeProcessor.shouldKeep(durationSeconds: duration, minVideoSeconds: feed.minVideoSeconds) {
                    continue
                }

                let filterEntry = Self.filterEntry(from: parsed)
                let filterResult = FilterEngine.apply(rules: filterRules, entry: filterEntry, feed: feedContext)
                if filterResult.drop { continue }

                let article = Article(
                    guid: parsed.guid,
                    title: parsed.title,
                    url: parsed.url ?? videoID.flatMap { YouTubeProcessor.watchURL(for: $0) },
                    author: parsed.author,
                    publishedAt: parsed.publishedAt,
                    summary: parsed.summary,
                    contentHTML: parsed.contentHTML,
                    estimatedReadingMinutes: ContentClassifier.consumeMinutes(
                        entryType: classified.kind,
                        words: ContentClassifier.wordCount(in: parsed.contentHTML ?? parsed.summary ?? ""),
                        durationSeconds: duration
                    ),
                    state: filterResult.star ? .saved : .queued,
                    isRemoteStarred: filterResult.star,
                    contentKind: classified.kind.rawValue,
                    durationSeconds: duration ?? 0,
                    imageURL: parsed.imageURL ?? videoID.flatMap { YouTubeProcessor.thumbnailURL(for: $0) },
                    videoID: videoID,
                    enclosureURL: parsed.enclosureURL,
                    enclosureMIME: parsed.enclosureMIME,
                    feed: feed
                )
                context.insert(article)
                index.register(article)
                inserted += 1
                continue
            }

            let filterEntry = Self.filterEntry(from: parsed)
            let filterResult = FilterEngine.apply(rules: filterRules, entry: filterEntry, feed: feedContext)
            if filterResult.drop { continue }

            let article = Article(
                guid: parsed.guid,
                title: parsed.title,
                url: parsed.url,
                author: parsed.author,
                publishedAt: parsed.publishedAt,
                summary: parsed.summary,
                contentHTML: parsed.contentHTML,
                estimatedReadingMinutes: ContentClassifier.consumeMinutes(
                    entryType: classified.kind,
                    words: ContentClassifier.wordCount(in: parsed.contentHTML ?? parsed.summary ?? ""),
                    durationSeconds: classified.durationSeconds
                ),
                state: filterResult.star ? .saved : .queued,
                isRemoteStarred: filterResult.star,
                contentKind: classified.kind.rawValue,
                durationSeconds: classified.durationSeconds ?? 0,
                imageURL: parsed.imageURL,
                videoID: classified.videoID,
                enclosureURL: parsed.enclosureURL,
                enclosureMIME: parsed.enclosureMIME,
                feed: feed
            )
            context.insert(article)
            index.register(article)
            inserted += 1
        }
        return inserted
    }

    private static func filterEntry(from parsed: ParsedArticle) -> FilterEntry {
        FilterEntry(
            title: parsed.title,
            author: parsed.author ?? "",
            url: parsed.url?.absoluteString ?? "",
            content: [parsed.summary, parsed.contentHTML].compactMap { $0 }.joined(separator: " ")
        )
    }

    private static let durationConcurrency = 2
    private static let durationBackfillLimit = 8

    private func enrichMissingYouTubeDurations(in context: ModelContext, limit: Int = 8) async {
        let missing = articlesMissingYouTubeDuration(in: context, limit: limit)
        guard !missing.isEmpty else { return }

        let metadata = youtubeMetadata
        let deckItems = (try? context.fetch(FetchDescriptor<DailyDeckItem>())) ?? []
        var iterator = missing.makeIterator()
        var inFlight = 0
        await withTaskGroup(of: (UUID, String?, Int?).self) { group in
            func enqueue() {
                while inFlight < Self.durationConcurrency, let article = iterator.next() {
                    let id = article.id
                    let videoID = article.videoID
                        ?? YouTubeProcessor.parseVideoID(from: article.url)
                        ?? YouTubeProcessor.parseVideoID(fromGUID: article.guid)
                    guard let videoID else { continue }
                    inFlight += 1
                    group.addTask {
                        (id, videoID, await metadata.fetchDuration(videoID: videoID, allowWatchHTML: false))
                    }
                }
            }
            enqueue()
            for await (id, videoID, duration) in group {
                inFlight -= 1
                if let article = missing.first(where: { $0.isStored && $0.id == id }) {
                    if let videoID, article.videoID == nil {
                        article.videoID = videoID
                    }
                    if let duration, duration > 0 {
                        _ = YouTubeProcessor.applyFetchedDuration(duration, to: article, deckItems: deckItems)
                    }
                }
                enqueue()
            }
        }
        try? context.save()
    }

    private func articlesMissingYouTubeDuration(in context: ModelContext, limit: Int) -> [Article] {
        let deckItems = ((try? context.fetch(FetchDescriptor<DailyDeckItem>())) ?? [])
            .sorted { $0.position < $1.position }
        var targets: [Article] = []
        var seen = Set<UUID>()
        for item in deckItems {
            guard let article = item.article, article.isStored else { continue }
            guard article.contentKind == "youtube", article.durationSeconds <= 0 else { continue }
            if seen.insert(article.id).inserted {
                targets.append(article)
            }
            if targets.count >= limit { return targets }
        }
        let youtube = "youtube"
        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { article in
                article.contentKind == youtube && article.durationSeconds <= 0
            }
        )
        descriptor.fetchLimit = max(limit * 2, 16)
        descriptor.sortBy = [SortDescriptor(\.publishedAt, order: .reverse)]
        let extra = ((try? context.fetch(descriptor)) ?? []).filter { article in
            article.isStored && !seen.contains(article.id)
        }
        for article in extra {
            targets.append(article)
            if targets.count >= limit { break }
        }
        return targets
    }

    func backfillYouTubeDurations(in context: ModelContext) async {
        await enrichMissingYouTubeDurations(in: context, limit: Self.durationBackfillLimit)
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

    private func identityArticles(in context: ModelContext) -> [Article] {
        var descriptor = FetchDescriptor<Article>()
        descriptor.propertiesToFetch = [\.guid, \.url]
        descriptor.relationshipKeyPathsForPrefetching = [\.feed]
        return (try? context.fetch(descriptor)) ?? []
    }

    private func isEmptyFeed(_ feed: Feed, in context: ModelContext) -> Bool {
        let feedID = feed.id
        var descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.feed?.id == feedID })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.isEmpty ?? true
    }
}

extension FeedService: FeedRepository {}
