import Foundation
import SwiftData

/// A durable, user-authored idea. Source fields are copied snapshots so notes
/// remain useful after an Article or feed is removed.
@Model
final class KnowledgeNote {
    @Attribute(.unique) var id: UUID
    var title: String
    var explanation: String
    var formattedExplanation: Data? = nil
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var isDraft: Bool = false
    /// Original capture text, retained separately when the explanation is refined.
    var draftText: String = ""
    /// JSON-encoded immutable snapshots. Kept as one attribute for portability.
    var revisionHistory: Data? = nil

    var sourceArticleID: UUID?
    var sourceTitle: String
    var sourceURL: URL?
    var sourceAuthor: String?
    var sourcePublishedAt: Date?
    var sourceKind: String?
    var sourceReferences: [String] = []

    var isDeleted: Bool { deletedAt != nil }

    /// Newest first for display. The stored archive is kept oldest-first.
    var revisions: [KnowledgeNoteRevision] {
        get {
            guard let revisionHistory,
                  let decoded = try? JSONDecoder().decode([KnowledgeNoteRevision].self, from: revisionHistory) else {
                return []
            }
            return decoded.sorted {
                if $0.savedAt != $1.savedAt { return $0.savedAt > $1.savedAt }
                return $0.id.uuidString > $1.id.uuidString
            }
        }
        set {
            let ordered = newValue.sorted {
                if $0.savedAt != $1.savedAt { return $0.savedAt < $1.savedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            revisionHistory = try? encoder.encode(ordered)
        }
    }

    init(
        id: UUID = UUID(),
        title: String,
        explanation: String,
        formattedExplanation: Data? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        isDraft: Bool = false,
        draftText: String = "",
        revisionHistory: Data? = nil,
        sourceArticleID: UUID? = nil,
        sourceTitle: String = "",
        sourceURL: URL? = nil,
        sourceAuthor: String? = nil,
        sourcePublishedAt: Date? = nil,
        sourceKind: String? = nil,
        sourceReferences: [String] = []
    ) {
        self.id = id
        self.title = title
        self.explanation = explanation
        self.formattedExplanation = formattedExplanation
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.isDraft = isDraft
        self.draftText = draftText
        self.revisionHistory = revisionHistory
        self.sourceArticleID = sourceArticleID
        self.sourceTitle = sourceTitle
        self.sourceURL = sourceURL
        self.sourceAuthor = sourceAuthor
        self.sourcePublishedAt = sourcePublishedAt
        self.sourceKind = sourceKind
        self.sourceReferences = sourceReferences
    }

}

nonisolated struct KnowledgeNoteRevision: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var savedAt: Date
    var title: String
    var explanation: String
    var formattedExplanation: Data?
    var isDraft: Bool
    var draftText: String
    var sourceTitle: String
    var sourceURL: String?
    var sourceAuthor: String?
    var sourcePublishedAt: Date?
    var sourceKind: String?
    var sourceReferences: [String]

    init(
        id: UUID = UUID(),
        savedAt: Date = .now,
        title: String,
        explanation: String,
        formattedExplanation: Data? = nil,
        isDraft: Bool,
        draftText: String,
        sourceTitle: String,
        sourceURL: String?,
        sourceAuthor: String?,
        sourcePublishedAt: Date?,
        sourceKind: String?,
        sourceReferences: [String]
    ) {
        self.id = id
        self.savedAt = savedAt
        self.title = title
        self.explanation = explanation
        self.formattedExplanation = formattedExplanation
        self.isDraft = isDraft
        self.draftText = draftText
        self.sourceTitle = sourceTitle
        self.sourceURL = sourceURL
        self.sourceAuthor = sourceAuthor
        self.sourcePublishedAt = sourcePublishedAt
        self.sourceKind = sourceKind
        self.sourceReferences = sourceReferences
    }

    func hasSamePayload(as other: KnowledgeNoteRevision) -> Bool {
        title == other.title
            && explanation == other.explanation
            && formattedExplanation == other.formattedExplanation
            && isDraft == other.isDraft
            && draftText == other.draftText
            && sourceTitle == other.sourceTitle
            && sourceURL == other.sourceURL
            && sourceAuthor == other.sourceAuthor
            && sourcePublishedAt == other.sourcePublishedAt
            && sourceKind == other.sourceKind
            && sourceReferences == other.sourceReferences
    }
}
