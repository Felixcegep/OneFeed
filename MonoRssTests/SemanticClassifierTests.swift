import Foundation
import Testing
@testable import OneFeed

struct SemanticClassifierTests {
    @Test func identicalYouTubeIDsAreExactDuplicatesDespiteOrthogonalVectors() {
        let item = makeItem(
            identityKey: "incoming",
            youtubeID: "dQw4w9WgXcQ",
            titleVector: [1, 0],
            contentVector: [1, 0]
        )
        let selfCopy = makeItem(
            identityKey: "incoming",
            youtubeID: "dQw4w9WgXcQ",
            titleVector: [1, 0],
            contentVector: [1, 0]
        )
        let consumedAt = Date(timeIntervalSince1970: 1_700_000_050)
        let memory = makeItem(
            identityKey: "remembered",
            youtubeID: "dQw4w9WgXcQ",
            titleVector: [0, 1],
            contentVector: [0, 1],
            consumedAt: consumedAt,
            storyClusterID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        )

        let verdict = SemanticClassifier.classify(item: item, against: [selfCopy, memory])

        #expect(verdict.relationship == .exactDuplicate)
        #expect(verdict.confidence == .certain)
        #expect(verdict.matchedIdentityKey == "remembered")
        #expect(verdict.matchedConsumedAt == consumedAt)
        #expect(verdict.storyClusterID == nil)
    }

    @Test func distantTitlesWithCloseContentAreTheSameStory() {
        let published = Date(timeIntervalSince1970: 1_700_000_000)
        let cluster = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let item = makeItem(
            identityKey: "verge",
            sourceTitle: "The Verge",
            publishedAt: published,
            titleVector: [1, 0],
            contentVector: [1, 0]
        )
        let content = vector(cosine: 0.9)
        let memory = makeItem(
            identityKey: "wirecutter",
            sourceTitle: "Wirecutter",
            publishedAt: published.addingTimeInterval(60 * 60),
            titleVector: [0, 1],
            contentVector: content,
            storyClusterID: cluster
        )

        #expect(cosineSimilarity([1, 0], [0, 1]) == 0)
        #expect(cosineSimilarity([1, 0], content) > 0.89)
        #expect(cosineSimilarity([1, 0], content) < 0.91)

        let verdict = SemanticClassifier.classify(item: item, against: [memory])

        #expect(verdict.relationship == .sameStory)
        #expect(verdict.confidence == .medium)
        #expect(verdict.matchedIdentityKey == "wirecutter")
        #expect(verdict.storyClusterID == cluster)
    }

    @Test func similarTitlesWithDistantContentStayNew() {
        let title = vector(cosine: 0.95)
        let content = vector(cosine: 0.4)
        let item = makeItem(
            identityKey: "incoming",
            titleVector: [1, 0],
            contentVector: [1, 0]
        )
        let memory = makeItem(
            identityKey: "other",
            sourceTitle: "Other",
            titleVector: title,
            contentVector: content
        )

        #expect(cosineSimilarity([1, 0], title) >= SemanticClassifier.nearDuplicateTitle)
        #expect(cosineSimilarity([1, 0], content) < SemanticClassifier.relatedContent)

        let verdict = SemanticClassifier.classify(item: item, against: [memory])

        #expect(verdict.relationship == .new)
        #expect(verdict.confidence == .low)
        #expect(verdict.matchedIdentityKey == nil)
    }

    @Test func identicalVectorsInDifferentLanguagesStayNew() {
        let item = makeItem(
            identityKey: "french",
            titleVector: [1, 0],
            contentVector: [1, 0],
            embeddingLanguage: "fr",
            embeddingRevision: 1
        )
        let memory = makeItem(
            identityKey: "english",
            titleVector: [1, 0],
            contentVector: [1, 0],
            embeddingLanguage: "en",
            embeddingRevision: 1
        )

        let verdict = SemanticClassifier.classify(item: item, against: [memory])

        #expect(verdict.relationship == .new)
        #expect(verdict.confidence == .low)
        #expect(verdict.matchedIdentityKey == nil)
    }

    @Test func closeTitleAndContentAreNearDuplicates() {
        let title = vector(cosine: 0.95)
        let content = vector(cosine: 0.95)
        let item = makeItem(
            identityKey: "incoming",
            titleVector: [1, 0],
            contentVector: [1, 0],
            hasGeminiSummary: false
        )
        let memory = makeItem(
            identityKey: "earlier",
            titleVector: title,
            contentVector: content,
            consumedAt: Date(timeIntervalSince1970: 80)
        )

        #expect(cosineSimilarity([1, 0], title) >= SemanticClassifier.nearDuplicateTitle)
        #expect(cosineSimilarity([1, 0], content) >= SemanticClassifier.nearDuplicateContent)
        #expect(cosineSimilarity([1, 0], content) < SemanticClassifier.certainNearDuplicateContent)

        let verdict = SemanticClassifier.classify(item: item, against: [memory])

        #expect(verdict.relationship == .nearDuplicate)
        #expect(verdict.confidence == .high)
        #expect(verdict.matchedIdentityKey == "earlier")
        #expect(verdict.matchedConsumedAt == Date(timeIntervalSince1970: 80))
        #expect(verdict.storyClusterID == nil)
    }

    @Test func geminiSummaryMakesAVeryCloseNearDuplicateCertain() {
        let item = makeItem(
            identityKey: "incoming",
            titleVector: [1, 0],
            contentVector: [1, 0],
            hasGeminiSummary: true
        )
        let memory = makeItem(
            identityKey: "earlier",
            titleVector: [1, 0],
            contentVector: [1, 0]
        )

        let verdict = SemanticClassifier.classify(item: item, against: [memory])

        #expect(verdict.relationship == .nearDuplicate)
        #expect(verdict.confidence == .certain)
    }

    private func makeItem(
        identityKey: String,
        youtubeID: String? = nil,
        normalizedURL: String? = nil,
        contentHash: String = "",
        sourceTitle: String = "Source",
        publishedAt: Date? = nil,
        titleVector: [Double]? = nil,
        contentVector: [Double]? = nil,
        embeddingLanguage: String = "en",
        embeddingRevision: Int = 1,
        hasGeminiSummary: Bool = false,
        consumedAt: Date? = nil,
        storyClusterID: UUID? = nil
    ) -> SemanticItem {
        SemanticItem(
            identityKey: identityKey,
            youtubeID: youtubeID,
            normalizedURL: normalizedURL,
            contentHash: contentHash,
            sourceTitle: sourceTitle,
            publishedAt: publishedAt,
            titleVector: titleVector,
            contentVector: contentVector,
            embeddingLanguage: embeddingLanguage,
            embeddingRevision: embeddingRevision,
            hasGeminiSummary: hasGeminiSummary,
            consumedAt: consumedAt,
            storyClusterID: storyClusterID
        )
    }

    /// Unit vector whose cosine with `[1, 0]` is `expected`.
    private func vector(cosine expected: Double) -> [Double] {
        [expected, (1 - expected * expected).squareRoot()]
    }

    private func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double {
        let dot = zip(lhs, rhs).reduce(0) { $0 + $1.0 * $1.1 }
        let left = lhs.reduce(0) { $0 + $1 * $1 }.squareRoot()
        let right = rhs.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard left > 0, right > 0 else { return 0 }
        return dot / (left * right)
    }
}
