import Foundation
import SwiftData

/// RSS bodies with at least this many words are treated as a full article (AUTO).
/// ~2 minutes at 220 wpm — below that, most feeds are still a teaser.
nonisolated let autoExtractMinWords = 400

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
        ContentClassifier.wordCount(in: html ?? "")
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

    func extractedHTML(for article: Article, policy: ArticleExtractionPolicy = ArticleExtractionPolicy(), alreadyEligible: Bool = false) async -> String? {
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            return article.contentHTML ?? article.summary
        }
        if !alreadyEligible {
            let articleID = article.id
            if let container = article.modelContext?.container {
                let shouldFetch = await Task.detached(priority: .utility) {
                    Self.shouldFetchStoredArticle(id: articleID, policy: policy, in: container)
                }.value
                guard shouldFetch else { return nil }
            } else {
                let existing = article.contentHTML ?? article.summary
                let kind = article.contentKind
                let shouldFetch = await Task.detached(priority: .utility) {
                    policy.shouldFetchPage(rssHTML: existing, kind: kind)
                }.value
                guard shouldFetch else { return existing }
            }
        }
        let existing = article.contentHTML ?? article.summary
        guard let url = article.url else { return existing }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("OneFeed/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return existing }
            let pageURL = http.url ?? url
            let slice = Data(data.prefix(maxBytes))
            let extractor = self.extractor
            return await Task.detached(priority: .utility) {
                let html = String(data: slice, encoding: .utf8) ?? String(decoding: slice, as: UTF8.self)
                return extractor.extract(fromHTML: html, pageURL: pageURL) ?? existing
            }.value
        } catch {
            return existing
        }
    }

    /// Reads the stored body on another context so a full article is not copied before the fetch decision.
    nonisolated static func shouldFetchStoredArticle(id articleID: UUID, policy: ArticleExtractionPolicy = ArticleExtractionPolicy(), in container: ModelContainer) -> Bool {
        let context = ModelContext(container)
        let matchID = articleID
        var descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.id == matchID })
        descriptor.fetchLimit = 1
        guard let stored = try? context.fetch(descriptor).first else { return false }
        return policy.shouldFetchPage(rssHTML: stored.contentHTML ?? stored.summary, kind: stored.contentKind)
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
        var bodies: [ExtractedBody] = []
        for article in targets {
            guard let html = await extractedHTML(for: article) else { continue }
            if html != article.contentHTML {
                let minutes = await Task.detached(priority: .utility) {
                    ContentClassifier.readingMinutes(words: ContentClassifier.wordCount(in: html))
                }.value
                article.contentHTML = html
                article.raiseReadingEstimate(minutes)
                bodies.append(
                    ExtractedBody(
                        articleID: article.id,
                        html: html,
                        estimatedMinutes: article.estimatedReadingMinutes
                    )
                )
            }
        }
        try? await LibraryIngestActor(modelContainer: context.container).persistExtractedBodies(bodies)
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
