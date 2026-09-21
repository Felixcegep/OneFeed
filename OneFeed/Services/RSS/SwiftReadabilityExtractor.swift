import Foundation
import SwiftReadability

/// Mozilla-style article extract. Relative links/images are resolved against
/// `pageURL`, so the existing Reader `about:blank` base URL can stay.
nonisolated struct SwiftReadabilityExtractor: ArticleExtracting {
    func extract(fromHTML html: String, pageURL: URL) -> String? {
        do {
            let reader = Readability(html: html, url: pageURL)
            guard let article = try reader.parse() else { return nil }
            let content = article.contentHTML.trimmingCharacters(in: .whitespacesAndNewlines)
            return content.isEmpty ? nil : content
        } catch {
            return nil
        }
    }
}
