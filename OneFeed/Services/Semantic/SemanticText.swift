import Foundation
import NaturalLanguage

/// Compact strings for sentence embeddings. Apple's model scores sentences, not full articles.
nonisolated enum SemanticText {
    private static let titleLimit = 200
    private static let excerptLimit = 600
    private static let contentLimit = 800
    private static let htmlTag = /<\/?[A-Za-z][^>]*>/

    static func detectLanguage(title: String, body: String) -> String {
        let sample = [title, body]
            .map(collapseWhitespace)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !sample.isEmpty else { return "en" }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        return recognizer.dominantLanguage?.rawValue ?? "en"
    }

    static func titleText(_ title: String) -> String {
        capped(collapseWhitespace(title), limit: titleLimit)
    }

    static func contentText(title: String, body: String, semanticSummary: String) -> String {
        let summary = semanticSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let block: String
        if summary.isEmpty {
            block = "TITLE:\n\(titleText(title))\n\nSUMMARY:\n\(plainExcerpt(body))"
        } else {
            block = summary
        }
        return capped(block, limit: contentLimit)
    }

    private static func plainExcerpt(_ body: String) -> String {
        let stripped = body.contains(htmlTag) ? body.replacing(htmlTag, with: " ") : body
        return capped(collapseWhitespace(stripped), limit: excerptLimit)
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func capped(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit))
    }
}
