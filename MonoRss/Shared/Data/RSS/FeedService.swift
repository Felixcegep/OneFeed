import Foundation
import SwiftData

enum FeedServiceError: LocalizedError {
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
    func addSource(from input: String, in context: ModelContext) async throws -> Feed
    func refresh(_ feed: Feed, in context: ModelContext) async throws
    func refreshAll(in context: ModelContext) async throws
}

@MainActor
final class FeedService {
    private let session: URLSession
    private let parser: FeedParser

    init(session: URLSession = .shared, parser: FeedParser = FeedParser()) {
        self.session = session
        self.parser = parser
    }

    func addSource(from input: String, in context: ModelContext) async throws -> Feed {
        guard let initialURL = Self.normalizedURL(from: input) else { throw FeedServiceError.invalidAddress }
        let (feedURL, parsed) = try await discoverAndParse(initialURL)
        let descriptor = FetchDescriptor<Feed>(predicate: #Predicate { $0.feedURL == feedURL })
        if let existing = try context.fetch(descriptor).first { return existing }

        let feed = Feed(title: parsed.title, websiteURL: parsed.websiteURL ?? initialURL, feedURL: feedURL, lastFetchedAt: .now)
        context.insert(feed)
        insert(parsed.articles, into: feed, in: context)
        try context.save()
        return feed
    }

    func refresh(_ feed: Feed, in context: ModelContext) async throws {
        var request = URLRequest(url: feed.feedURL)
        if let etag = feed.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let modified = feed.lastModified { request.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FeedServiceError.invalidResponse }
        if http.statusCode == 304 { feed.lastFetchedAt = .now; try context.save(); return }
        guard (200..<300).contains(http.statusCode) else { throw FeedServiceError.http(http.statusCode) }
        let parsed = try parser.parse(data)
        feed.title = parsed.title
        feed.websiteURL = parsed.websiteURL ?? feed.websiteURL
        feed.etag = http.value(forHTTPHeaderField: "ETag")
        feed.lastModified = http.value(forHTTPHeaderField: "Last-Modified")
        feed.lastFetchedAt = .now
        insert(parsed.articles, into: feed, in: context)
        try context.save()
    }

    func refreshAll(in context: ModelContext) async throws {
        let feeds = try context.fetch(FetchDescriptor<Feed>(predicate: #Predicate { $0.isEnabled && $0.remoteID == nil }))
        var firstError: Error?
        for feed in feeds {
            do { try await refresh(feed, in: context) } catch { firstError = firstError ?? error }
        }
        if let firstError { throw firstError }
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

    private func insert(_ parsedArticles: [ParsedArticle], into feed: Feed, in context: ModelContext) {
        let existing = Set(feed.articles.map(\.guid))
        for parsed in parsedArticles where !existing.contains(parsed.guid) {
            context.insert(Article(
                guid: parsed.guid,
                title: parsed.title,
                url: parsed.url,
                author: parsed.author,
                publishedAt: parsed.publishedAt,
                summary: parsed.summary,
                contentHTML: parsed.contentHTML,
                estimatedReadingMinutes: parsed.estimatedReadingMinutes,
                feed: feed
            ))
        }
    }

    static func normalizedURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        return URL(string: "https://\(trimmed)")
    }

    static func discoverFeedURL(in html: String, relativeTo baseURL: URL) -> URL? {
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
