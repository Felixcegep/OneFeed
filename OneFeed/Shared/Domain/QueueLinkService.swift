import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

enum QueueLinkError: LocalizedError {
    case invalidAddress
    case channelOnly

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            "That doesn’t look like a link."
        case .channelOnly:
            "That’s a YouTube channel. Add it as a source in Feed, then queue a video from there."
        }
    }
}

@MainActor
struct QueueLinkService {
    private let session: URLSession
    var fetchesMetadata: Bool

    init(session: URLSession = .shared, fetchesMetadata: Bool? = nil) {
        self.session = session
        if let fetchesMetadata {
            self.fetchesMetadata = fetchesMetadata
        } else {
            self.fetchesMetadata = !ProcessInfo.processInfo.arguments.contains("-uiTesting")
        }
    }

    static var pasteboardURL: URL? {
        let raw: String?
        #if os(macOS)
        raw = NSPasteboard.general.string(forType: .URL)
            ?? NSPasteboard.general.string(forType: .string)
        #elseif canImport(UIKit)
        raw = UIPasteboard.general.url?.absoluteString ?? UIPasteboard.general.string
        #else
        raw = nil
        #endif
        guard let raw, let url = FeedService.normalizedURL(from: raw) else { return nil }
        let scheme = url.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    @discardableResult
    func add(urlString: String, in context: ModelContext) async throws -> Article {
        guard let url = FeedService.normalizedURL(from: urlString) else { throw QueueLinkError.invalidAddress }
        let scheme = url.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { throw QueueLinkError.invalidAddress }

        let classified = ContentClassifier.classify(
            url: url,
            title: url.lastPathComponent,
            summary: nil,
            contentHTML: nil,
            enclosureMIME: nil,
            durationSeconds: nil
        )
        if classified.kind == .youtube, classified.videoID == nil, classified.channelID != nil {
            throw QueueLinkError.channelOnly
        }

        if let existing = existingArticle(matching: url, in: context) {
            try park(existing, in: context)
            return existing
        }

        if ImportedDocumentKind.infer(url: url) != nil {
            return try await ImportedDocumentService(session: session).importRemote(url: url, in: context)
        }

        var title = Self.fallbackTitle(for: url)
        var imageURL = classified.videoID.flatMap { YouTubeProcessor.thumbnailURL(for: $0) }
        var duration = 0
        var html: String?

        if fetchesMetadata {
            if classified.kind == .youtube, let videoID = classified.videoID {
                duration = await YouTubeMetadataService(session: session).fetchDuration(videoID: videoID) ?? 0
            }
            if let preview = await pagePreview(for: url) {
                if !preview.title.isEmpty { title = preview.title }
                if imageURL == nil { imageURL = preview.imageURL }
                html = preview.html
            }
        }

        let minutes: Int
        if classified.kind == .youtube, duration > 0 {
            minutes = max(1, Int((Double(duration) / 60.0).rounded()))
        } else {
            minutes = max(1, classified.estimatedMinutes)
        }

        let article = Article(
            guid: url.absoluteString,
            title: title,
            url: url,
            publishedAt: .now,
            contentHTML: html,
            estimatedReadingMinutes: minutes,
            state: .saved,
            isRemoteStarred: true,
            contentKind: classified.kind.rawValue,
            durationSeconds: duration,
            imageURL: imageURL,
            videoID: classified.videoID,
            libraryUpdatedAt: .now
        )
        article.completedAt = .now
        context.insert(article)
        LibraryChange.note(article)
        try context.save()
        return article
    }

    func park(_ article: Article, in context: ModelContext) throws {
        guard article.isStored else { return }
        if article.state == .saved {
            article.completedAt = .now
            LibraryChange.note(article)
            try context.save()
            return
        }
        try ArticleQueueService().complete(article, as: .saved, in: context)
    }

    private func existingArticle(matching url: URL, in context: ModelContext) -> Article? {
        let key = ArticleIdentity.normalizedURLString(url)
        let articles = (try? context.fetch(FetchDescriptor<Article>())) ?? []
        return articles.first { ArticleIdentity.normalizedURLString($0.url) == key }
    }

    private func pagePreview(for url: URL) async -> (title: String, imageURL: URL?, html: String?)? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("OneFeed/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            let pageURL = http.url ?? url
            let html = String(data: Data(data.prefix(512_000)), encoding: .utf8)
                ?? String(decoding: data.prefix(512_000), as: UTF8.self)
            let title = Self.parseTitle(in: html) ?? Self.fallbackTitle(for: pageURL)
            let image = Self.parseImage(in: html, relativeTo: pageURL)
            return (title, image, html)
        } catch {
            return nil
        }
    }

    static func fallbackTitle(for url: URL) -> String {
        let last = url.lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !last.isEmpty, last != "/", !last.contains(".") || last.split(separator: ".").count == 1 {
            return last.localizedCapitalized
        }
        return url.host()?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
    }

    static func parseTitle(in html: String) -> String? {
        if let og = firstMatch(#"<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']"#, in: html)
            ?? firstMatch(#"<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:title["']"#, in: html) {
            return decode(og)
        }
        if let title = firstMatch(#"<title[^>]*>([^<]+)</title>"#, in: html) {
            return decode(title)
        }
        return nil
    }

    static func parseImage(in html: String, relativeTo base: URL) -> URL? {
        let raw = firstMatch(#"<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']"#, in: html)
            ?? firstMatch(#"<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']"#, in: html)
        guard let raw else { return nil }
        return URL(string: decode(raw), relativeTo: base)?.absoluteURL
    }

    private static func firstMatch(_ pattern: String, in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: html) else { return nil }
        let value = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func decode(_ string: String) -> String {
        ContentClassifier.stripHTML(string)
    }
}
