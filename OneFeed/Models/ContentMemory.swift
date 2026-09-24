import CryptoKit
import Foundation
import SwiftData

nonisolated enum SemanticState: String, Sendable {
    case raw
    case preliminary
    case enriched
    case final
}

nonisolated enum ContentRelationship: String, Sendable {
    case exactDuplicate
    case nearDuplicate
    case sameStory
    case related
    case new
}

nonisolated enum SemanticConfidence: String, Sendable {
    case certain
    case high
    case medium
    case low
}

/// Float32 little-endian vectors and a stable hash of the text that was embedded.
nonisolated enum ContentVector {
    static func pack(_ values: [Double]) -> Data {
        var data = Data(capacity: values.count * 4)
        for value in values {
            var bits = Float(value).bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        return data
    }

    static func unpack(_ data: Data?) -> [Double]? {
        guard let data else { return nil }
        let width = 4
        guard data.count.isMultiple(of: width) else { return nil }
        let count = data.count / width
        var values = [Double]()
        values.reserveCapacity(count)
        data.withUnsafeBytes { raw in
            for index in 0..<count {
                let loaded = raw.loadUnaligned(fromByteOffset: index * width, as: UInt32.self)
                values.append(Double(Float(bitPattern: UInt32(littleEndian: loaded))))
            }
        }
        return values
    }

    /// SHA256 hex of `"\(title)\n\(body)"` after trimming the joined string.
    static func hash(title: String, body: String) -> String {
        let text = "\(title)\n\(body)".trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Device-local semantic memory. It is not a relationship on Article or Feed,
/// so deleting a story does not delete what was learned from it.
@Model
final class ContentMemory {
    @Attribute(.unique) var id: UUID
    /// `video:<youtubeID>` when a video id exists, otherwise `url:<normalizedURL>`.
    @Attribute(.unique) var identityKey: String
    var canonicalURL: String?
    var externalID: String?
    var sourceType: String
    var publishedAt: Date?
    var title: String
    var itemDescription: String
    var languageCode: String
    var semanticText: String
    var semanticSummary: String
    var summarySource: String
    var contentHash: String
    var titleVector: Data?
    var contentVector: Data?
    var embeddingProvider: String = "apple-nl"
    var embeddingRevision: Int = 0
    var embeddingLanguage: String = ""
    var embeddingDimension: Int = 0
    var stateRaw: String = SemanticState.raw.rawValue
    var relationshipRaw: String = ContentRelationship.new.rawValue
    var confidenceRaw: String = SemanticConfidence.low.rawValue
    var firstSeenAt: Date
    var consumedAt: Date?
    var duplicateOfKey: String?
    var storyClusterID: UUID?
    var matchedConsumedAt: Date?

    var state: SemanticState {
        get { SemanticState(rawValue: stateRaw) ?? .raw }
        set { stateRaw = newValue.rawValue }
    }

    var relationship: ContentRelationship {
        get { ContentRelationship(rawValue: relationshipRaw) ?? .new }
        set { relationshipRaw = newValue.rawValue }
    }

    var confidence: SemanticConfidence {
        get { SemanticConfidence(rawValue: confidenceRaw) ?? .low }
        set { confidenceRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        identityKey: String,
        canonicalURL: String? = nil,
        externalID: String? = nil,
        sourceType: String = "article",
        publishedAt: Date? = nil,
        title: String,
        itemDescription: String = "",
        languageCode: String = "",
        semanticText: String = "",
        semanticSummary: String = "",
        summarySource: String = "",
        contentHash: String = "",
        titleVector: Data? = nil,
        contentVector: Data? = nil,
        embeddingProvider: String = "apple-nl",
        embeddingRevision: Int = 0,
        embeddingLanguage: String = "",
        embeddingDimension: Int = 0,
        stateRaw: String = SemanticState.raw.rawValue,
        relationshipRaw: String = ContentRelationship.new.rawValue,
        confidenceRaw: String = SemanticConfidence.low.rawValue,
        firstSeenAt: Date = .now,
        consumedAt: Date? = nil,
        duplicateOfKey: String? = nil,
        storyClusterID: UUID? = nil,
        matchedConsumedAt: Date? = nil
    ) {
        self.id = id
        self.identityKey = identityKey
        self.canonicalURL = canonicalURL
        self.externalID = externalID
        self.sourceType = sourceType
        self.publishedAt = publishedAt
        self.title = title
        self.itemDescription = itemDescription
        self.languageCode = languageCode
        self.semanticText = semanticText
        self.semanticSummary = semanticSummary
        self.summarySource = summarySource
        self.contentHash = contentHash
        self.titleVector = titleVector
        self.contentVector = contentVector
        self.embeddingProvider = embeddingProvider
        self.embeddingRevision = embeddingRevision
        self.embeddingLanguage = embeddingLanguage
        self.embeddingDimension = embeddingDimension
        self.stateRaw = stateRaw
        self.relationshipRaw = relationshipRaw
        self.confidenceRaw = confidenceRaw
        self.firstSeenAt = firstSeenAt
        self.consumedAt = consumedAt
        self.duplicateOfKey = duplicateOfKey
        self.storyClusterID = storyClusterID
        self.matchedConsumedAt = matchedConsumedAt
    }

    /// `video:<youtubeID>` when a video id exists, otherwise `url:<normalizedURL>`.
    nonisolated static func makeIdentityKey(externalID: String?, canonicalURL: String?) -> String {
        let videoID = externalID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !videoID.isEmpty { return "video:\(videoID)" }
        let trimmed = canonicalURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalized = URL(string: trimmed).flatMap(ArticleIdentity.normalizedURLString) ?? trimmed
        return "url:\(normalized)"
    }
}
