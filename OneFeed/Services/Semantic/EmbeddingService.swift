import Foundation
import NaturalLanguage

/// On-device sentence embeddings. The actor keeps at most one `NLEmbedding` per language
/// and never lends that model to a concurrent call.
actor EmbeddingService {
    nonisolated struct EmbeddedVectors: Sendable {
        var title: [Double]
        var content: [Double]
        var language: String
        var revision: Int
    }

    private var sentenceEmbeddings: [NLLanguage: NLEmbedding] = [:]

    func embed(
        title: String,
        body: String,
        semanticSummary: String,
        languageCode: String?
    ) async -> EmbeddedVectors? {
        let code = resolvedLanguageCode(title: title, body: body, languageCode: languageCode)
        let language = NLLanguage(rawValue: code)
        // A missing model stays nil. Falling back to English would mix incomparable spaces.
        guard let embedding = sentenceEmbedding(for: language) else { return nil }
        let titleText = SemanticText.titleText(title)
        let contentText = SemanticText.contentText(
            title: title,
            body: body,
            semanticSummary: semanticSummary
        )
        guard let titleVector = embedding.vector(for: titleText),
              let contentVector = embedding.vector(for: contentText) else {
            return nil
        }
        return EmbeddedVectors(
            title: titleVector,
            content: contentVector,
            language: language.rawValue,
            revision: NLEmbedding.currentRevision(for: language)
        )
    }

    private func sentenceEmbedding(for language: NLLanguage) -> NLEmbedding? {
        if let cached = sentenceEmbeddings[language] {
            return cached
        }
        let revision = NLEmbedding.currentRevision(for: language)
        guard let created = NLEmbedding.sentenceEmbedding(for: language, revision: revision) else {
            return nil
        }
        sentenceEmbeddings[language] = created
        return created
    }

    private func resolvedLanguageCode(title: String, body: String, languageCode: String?) -> String {
        if let languageCode {
            let trimmed = languageCode.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return SemanticText.detectLanguage(title: title, body: body)
    }
}
