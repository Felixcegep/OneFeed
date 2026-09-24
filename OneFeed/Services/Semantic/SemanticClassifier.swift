import Foundation

nonisolated struct SemanticItem: Sendable, Equatable {
    var identityKey: String
    var youtubeID: String?
    var normalizedURL: String?
    var contentHash: String
    var sourceTitle: String
    var publishedAt: Date?
    var titleVector: [Double]?
    var contentVector: [Double]?
    var embeddingLanguage: String
    var embeddingRevision: Int
    var hasGeminiSummary: Bool
    var consumedAt: Date?
    var storyClusterID: UUID?
}

nonisolated struct SemanticVerdict: Sendable, Equatable {
    var relationship: ContentRelationship
    var confidence: SemanticConfidence
    var matchedIdentityKey: String?
    var matchedConsumedAt: Date?
    var storyClusterID: UUID?
}

/// Pure relationship rules. Callers pass vectors; this type never loads `NLEmbedding`.
nonisolated enum SemanticClassifier {
    static let nearDuplicateTitle = 0.92
    static let nearDuplicateContent = 0.92
    /// Strong paraphrase of the body. A clickbait title can still be the same story.
    static let sameStoryContent = 0.84
    /// Weaker body overlap is the same story only when the headline also agrees.
    static let sameStorySupportedContent = 0.78
    static let sameStoryTitleSupport = 0.45
    static let relatedContent = 0.72
    static let certainNearDuplicateContent = 0.96
    static let sameStoryWindow: TimeInterval = 96 * 60 * 60

    static func classify(item: SemanticItem, against memories: [SemanticItem]) -> SemanticVerdict {
        let others = memories.filter { $0.identityKey != item.identityKey }
        if let exact = closestContentMatch(item, among: others.filter { sharesHardIdentity(item, $0) }) {
            return verdict(.exactDuplicate, .certain, match: exact.memory, storyClusterID: nil)
        }

        let comparable = others.filter {
            $0.embeddingLanguage == item.embeddingLanguage && $0.embeddingRevision == item.embeddingRevision
        }
        guard let best = closestContentMatch(item, among: comparable) else {
            return unmatched
        }

        if best.title >= nearDuplicateTitle, best.content >= nearDuplicateContent {
            let confidence: SemanticConfidence = item.hasGeminiSummary && best.content >= certainNearDuplicateContent
                ? .certain
                : .high
            return verdict(.nearDuplicate, confidence, match: best.memory, storyClusterID: nil)
        }
        if isSameStory(title: best.title, content: best.content),
           publishedWithinSameStoryWindow(item, best.memory),
           sourcesDiffer(item, best.memory) {
            let confidence: SemanticConfidence = item.hasGeminiSummary ? .high : .medium
            return verdict(.sameStory, confidence, match: best.memory, storyClusterID: best.memory.storyClusterID)
        }
        if best.content >= relatedContent {
            return verdict(.related, .low, match: best.memory, storyClusterID: nil)
        }
        return unmatched
    }

    private static let unmatched = SemanticVerdict(
        relationship: .new,
        confidence: .low,
        matchedIdentityKey: nil,
        matchedConsumedAt: nil,
        storyClusterID: nil
    )

    private struct ScoredMatch {
        var memory: SemanticItem
        var title: Double
        var content: Double
    }

    private static func closestContentMatch(_ item: SemanticItem, among memories: [SemanticItem]) -> ScoredMatch? {
        var best: ScoredMatch?
        for memory in memories {
            let scored = ScoredMatch(
                memory: memory,
                title: similarity(item, memory, item.titleVector, memory.titleVector),
                content: similarity(item, memory, item.contentVector, memory.contentVector)
            )
            guard let current = best else {
                best = scored
                continue
            }
            if rank(scored) > rank(current) {
                best = scored
            }
        }
        return best
    }

    private static func sharesHardIdentity(_ item: SemanticItem, _ memory: SemanticItem) -> Bool {
        if let left = nonEmpty(item.youtubeID), let right = nonEmpty(memory.youtubeID), left == right {
            return true
        }
        if let left = nonEmpty(item.normalizedURL), let right = nonEmpty(memory.normalizedURL), left == right {
            return true
        }
        if let left = nonEmpty(item.contentHash), let right = nonEmpty(memory.contentHash), left == right {
            return true
        }
        return false
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Content carries the event. Title support keeps a shared product name from winning over the real story.
    private static func isSameStory(title: Double, content: Double) -> Bool {
        if content >= sameStoryContent { return true }
        return content >= sameStorySupportedContent && title >= sameStoryTitleSupport
    }

    private static func rank(_ scored: ScoredMatch) -> Double {
        if scored.title < 0.35 { return scored.content * 0.55 }
        return (0.35 * scored.title) + (0.65 * scored.content)
    }

    private static func publishedWithinSameStoryWindow(_ item: SemanticItem, _ memory: SemanticItem) -> Bool {
        guard let left = item.publishedAt, let right = memory.publishedAt else { return false }
        return abs(left.timeIntervalSince(right)) <= sameStoryWindow
    }

    private static func sourcesDiffer(_ item: SemanticItem, _ memory: SemanticItem) -> Bool {
        item.sourceTitle.caseInsensitiveCompare(memory.sourceTitle) != .orderedSame
    }

    private static func similarity(
        _ item: SemanticItem,
        _ memory: SemanticItem,
        _ itemVector: [Double]?,
        _ memoryVector: [Double]?
    ) -> Double {
        guard item.embeddingLanguage == memory.embeddingLanguage,
              item.embeddingRevision == memory.embeddingRevision,
              let itemVector,
              let memoryVector else {
            return 0
        }
        return cosine(itemVector, memoryVector)
    }

    /// Higher is more similar. Mismatched or empty vectors score 0.
    private static func cosine(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var dot = 0.0
        var leftNorm = 0.0
        var rightNorm = 0.0
        for index in lhs.indices {
            let left = lhs[index]
            let right = rhs[index]
            dot += left * right
            leftNorm += left * left
            rightNorm += right * right
        }
        let denominator = leftNorm.squareRoot() * rightNorm.squareRoot()
        guard denominator > 0 else { return 0 }
        return dot / denominator
    }

    private static func verdict(
        _ relationship: ContentRelationship,
        _ confidence: SemanticConfidence,
        match: SemanticItem,
        storyClusterID: UUID?
    ) -> SemanticVerdict {
        SemanticVerdict(
            relationship: relationship,
            confidence: confidence,
            matchedIdentityKey: match.identityKey,
            matchedConsumedAt: match.consumedAt,
            storyClusterID: storyClusterID
        )
    }
}
