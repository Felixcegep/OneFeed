import Foundation
import SwiftData

/// RSS bodies with at least this many words are treated as a full article (AUTO).
nonisolated let autoExtractMinWords = 80

enum ExtractMode: String, Codable, Sendable, CaseIterable {
    case off
    case automatic
    case always
}

nonisolated protocol ArticleExtracting: Sendable {
    func extract(fromHTML html: String, pageURL: URL) -> String?
}

/// Word-count gate used before any network extract. SwiftReadability plugs in
/// behind `ArticleExtracting`; this type decides whether to fetch at all.
nonisolated struct ArticleExtractionPolicy: Sendable {
    var mode: ExtractMode = .automatic
    var minWords: Int = autoExtractMinWords

    func shouldFetchPage(rssHTML: String?, kind: String) -> Bool {
        if kind != "article" { return false }
        switch mode {
        case .off: return false
        case .always: return true
        case .automatic:
            return wordCount(in: rssHTML) < minWords
        }
    }

    func wordCount(in html: String?) -> Int {
        let plain = (html ?? "").replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return plain.split(whereSeparator: \.isWhitespace).count
    }
}

/// Fetches the article URL and runs an extractor. Call only for the current
/// Today card and maybe the next few — not for every item in background refresh.
@MainActor
final class ArticleExtractionService {
    private let session: URLSession
    private let extractor: any ArticleExtracting
    private let maxBytes = 1_048_576

    init(session: URLSession = .shared, extractor: any ArticleExtracting = SwiftReadabilityExtractor()) {
        self.session = session
        self.extractor = extractor
    }

    func extractedHTML(for article: Article, policy: ArticleExtractionPolicy = ArticleExtractionPolicy()) async -> String? {
        let existing = article.contentHTML ?? article.summary
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") { return existing }
        guard policy.shouldFetchPage(rssHTML: existing, kind: article.contentKind) else { return existing }
        guard let url = article.url else { return existing }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("OneFeed/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return existing }
            let pageURL = http.url ?? url
            let slice = data.prefix(maxBytes)
            let html = String(data: slice, encoding: .utf8) ?? String(decoding: slice, as: UTF8.self)
            return extractor.extract(fromHTML: html, pageURL: pageURL) ?? existing
        } catch {
            return existing
        }
    }

    /// Full-text only the current Today card and the next couple — not the whole library.
    func enrichUpcoming(in context: ModelContext, from item: DailyDeckItem?, extraQueued: Int = 2) async {
        guard let deck = item?.deck ?? (try? DailyDeckService().todayDeck(in: context)) else { return }
        let currentPosition = item?.position ?? 0
        let targets = deck.items
            .sorted { $0.position < $1.position }
            .filter { $0.position >= currentPosition }
            .prefix(1 + extraQueued)
            .compactMap(\.article)
        for article in targets {
            if let html = await extractedHTML(for: article), html != article.contentHTML {
                article.contentHTML = html
            }
        }
        try? context.save()
    }
}

/// Test double that keeps downloaded HTML. Production uses SwiftReadabilityExtractor.
nonisolated struct PassthroughHTMLExtractor: ArticleExtracting {
    func extract(fromHTML html: String, pageURL: URL) -> String? {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 80 else { return nil }
        return trimmed
    }
}
