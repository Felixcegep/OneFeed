import Foundation
import SwiftData

enum KnowledgeNoteStoreError: LocalizedError {
    case emptyTitle
    case emptyExplanation
    case emptyDraft
    case sourceRequired
    case invalidSourceReference
    case deletedNote

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            return String(localized: "Enter a title for this idea.")
        case .emptyExplanation:
            return String(localized: "Add your explanation in your own words.")
        case .emptyDraft:
            return String(localized: "Add some captured text before saving this draft.")
        case .sourceRequired:
            return String(localized: "Add a source before finishing this idea.")
        case .invalidSourceReference:
            return String(localized: "Each source must be a web address with a host.")
        case .deletedNote:
            return String(localized: "This idea has been deleted.")
        }
    }
}

@MainActor
enum KnowledgeNoteStore {
    @discardableResult
    static func create(
        title: String,
        explanation: String,
        formattedExplanation: Data? = nil,
        article: Article? = nil,
        isDraft: Bool = false,
        draftText: String = "",
        sourceReferences: [String] = [],
        in context: ModelContext
    ) throws -> KnowledgeNote {
        let copiedSource = article.map { source -> (url: URL?, isAttributed: Bool) in
            let candidate: URL?
            if source.contentKind == "youtube",
               let videoID = source.videoID,
               let watchURL = YouTubeProcessor.watchURL(for: videoID) {
                candidate = watchURL
            } else {
                candidate = source.url
            }
            return (candidate, !source.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        let copiedURL = copiedSource?.url
        let cleanReferences = try normalizedSourceReferences(sourceReferences, allowIncomplete: isDraft)
        let (cleanTitle, cleanExplanation, preservedDraftText) = try validated(
            title: title,
            explanation: explanation,
            isDraft: isDraft,
            draftText: draftText,
            sourceURL: copiedURL,
            hasAttributedSource: copiedSource != nil && copiedSource?.isAttributed == true,
            sourceReferences: cleanReferences,
            fallbackTitleForDraft: true
        )
        let storedExplanation = formattedExplanation?.isEmpty == false ? explanation : cleanExplanation
        let now = Date.now
        let note = KnowledgeNote(
            title: cleanTitle,
            explanation: storedExplanation,
            formattedExplanation: formattedExplanation,
            createdAt: now,
            updatedAt: now,
            isDraft: isDraft,
            draftText: preservedDraftText,
            sourceArticleID: article?.id,
            sourceTitle: article?.title ?? "",
            sourceURL: copiedURL,
            sourceAuthor: article?.author.flatMap(nonempty),
            sourcePublishedAt: article?.publishedAt,
            sourceKind: article?.contentKind,
            sourceReferences: cleanReferences
        )
        note.revisions = [revision(of: note, savedAt: now)]
        context.insert(note)
        do {
            try context.save()
        } catch {
            context.delete(note)
            throw error
        }
        LibraryChange.note(note)
        return note
    }

    static func update(
        _ note: KnowledgeNote,
        title: String,
        explanation: String,
        formattedExplanation: Data? = nil,
        isDraft: Bool? = nil,
        draftText: String? = nil,
        sourceReferences: [String]? = nil,
        in context: ModelContext
    ) throws {
        guard !note.isDeleted else { throw KnowledgeNoteStoreError.deletedNote }
        let nextIsDraft = isDraft ?? note.isDraft
        let cleanReferences = try normalizedSourceReferences(
            sourceReferences ?? note.sourceReferences,
            allowIncomplete: nextIsDraft
        )
        let cleanDraftInput: String
        if let draftText {
            cleanDraftInput = draftText
        } else if note.draftText.isEmpty, nextIsDraft {
            cleanDraftInput = explanation
        } else {
            cleanDraftInput = note.draftText
        }
        let (cleanTitle, cleanExplanation, cleanDraftText) = try validated(
            title: title,
            explanation: explanation,
            isDraft: nextIsDraft,
            draftText: cleanDraftInput,
            sourceURL: note.sourceURL.flatMap { validWebURL($0.absoluteString) },
            hasAttributedSource: note.sourceArticleID != nil
                && !note.sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            sourceReferences: cleanReferences,
            fallbackTitleForDraft: true
        )
        let nextFormattedExplanation: Data?
        let preserveExplanationWhitespace: Bool
        if let formattedExplanation {
            nextFormattedExplanation = formattedExplanation.isEmpty ? nil : formattedExplanation
            preserveExplanationWhitespace = !formattedExplanation.isEmpty
        } else if explanation == note.explanation {
            nextFormattedExplanation = note.formattedExplanation
            preserveExplanationWhitespace = note.formattedExplanation?.isEmpty == false
        } else {
            nextFormattedExplanation = nil
            preserveExplanationWhitespace = false
        }
        let storedExplanation = preserveExplanationWhitespace ? explanation : cleanExplanation
        let oldTitle = note.title
        let oldExplanation = note.explanation
        let oldFormattedExplanation = note.formattedExplanation
        let oldRevisionHistory = note.revisionHistory
        let oldUpdatedAt = note.updatedAt
        let oldIsDraft = note.isDraft
        let oldDraftText = note.draftText
        let oldSourceReferences = note.sourceReferences
        let previousRevision = revision(of: note, savedAt: note.updatedAt)
        let now = Date.now
        let newRevision = revision(
            title: cleanTitle,
            explanation: storedExplanation,
            formattedExplanation: nextFormattedExplanation,
            isDraft: nextIsDraft,
            draftText: cleanDraftText,
            sourceTitle: note.sourceTitle,
            sourceURL: note.sourceURL?.absoluteString,
            sourceAuthor: note.sourceAuthor,
            sourcePublishedAt: note.sourcePublishedAt,
            sourceKind: note.sourceKind,
            sourceReferences: cleanReferences,
            savedAt: now
        )
        var history = note.revisions
        if !previousRevision.hasSamePayload(as: newRevision) {
            if !history.contains(where: { $0.hasSamePayload(as: previousRevision) }) {
                history.append(previousRevision)
            }
            history.append(newRevision)
            note.revisions = history
        }
        note.title = cleanTitle
        note.explanation = storedExplanation
        note.formattedExplanation = nextFormattedExplanation
        note.isDraft = nextIsDraft
        note.draftText = cleanDraftText
        note.sourceReferences = cleanReferences
        note.updatedAt = now
        do {
            try context.save()
        } catch {
            note.title = oldTitle
            note.explanation = oldExplanation
            note.formattedExplanation = oldFormattedExplanation
            note.revisionHistory = oldRevisionHistory
            note.isDraft = oldIsDraft
            note.draftText = oldDraftText
            note.sourceReferences = oldSourceReferences
            note.updatedAt = oldUpdatedAt
            throw error
        }
        LibraryChange.note(note)
    }

    static func delete(_ note: KnowledgeNote, in context: ModelContext) throws {
        guard !note.isDeleted else { return }
        let oldDeletedAt = note.deletedAt
        let oldUpdatedAt = note.updatedAt
        let now = Date.now
        note.deletedAt = now
        note.updatedAt = now
        do {
            try context.save()
        } catch {
            note.deletedAt = oldDeletedAt
            note.updatedAt = oldUpdatedAt
            throw error
        }
        LibraryChange.note(note)
    }

    private static func validated(
        title: String,
        explanation: String,
        isDraft: Bool,
        draftText: String,
        sourceURL: URL?,
        hasAttributedSource: Bool,
        sourceReferences: [String],
        fallbackTitleForDraft: Bool
    ) throws -> (String, String, String) {
        var cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanExplanation = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty || (isDraft && fallbackTitleForDraft) else {
            throw KnowledgeNoteStoreError.emptyTitle
        }
        if cleanTitle.isEmpty { cleanTitle = String(localized: "Untitled draft") }

        if isDraft {
            let hasDraftText = !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard hasDraftText || !cleanExplanation.isEmpty else {
                throw KnowledgeNoteStoreError.emptyDraft
            }
            let preservedDraftText = hasDraftText ? draftText : explanation
            return (cleanTitle, cleanExplanation, preservedDraftText)
        }

        guard !cleanExplanation.isEmpty else { throw KnowledgeNoteStoreError.emptyExplanation }
        guard hasAttributedSource
            || sourceURL.flatMap({ validWebURL($0.absoluteString) }) != nil
            || !sourceReferences.isEmpty else {
            throw KnowledgeNoteStoreError.sourceRequired
        }
        return (cleanTitle, cleanExplanation, draftText)
    }

    private static func normalizedSourceReferences(
        _ references: [String],
        allowIncomplete: Bool
    ) throws -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for reference in references {
            let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let stored: String
            if let url = validWebURL(trimmed) {
                stored = url.absoluteString
            } else if allowIncomplete {
                stored = trimmed
            } else {
                throw KnowledgeNoteStoreError.invalidSourceReference
            }
            if seen.insert(stored).inserted { normalized.append(stored) }
        }
        return normalized
    }

    private static func validWebURL(_ rawValue: String) -> URL? {
        guard let components = URLComponents(string: rawValue),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty,
              let url = components.url else { return nil }
        return url
    }

    private static func nonempty(_ value: String) -> String? {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func revision(of note: KnowledgeNote, savedAt: Date) -> KnowledgeNoteRevision {
        revision(
            title: note.title,
            explanation: note.explanation,
            formattedExplanation: note.formattedExplanation,
            isDraft: note.isDraft,
            draftText: note.draftText,
            sourceTitle: note.sourceTitle,
            sourceURL: note.sourceURL?.absoluteString,
            sourceAuthor: note.sourceAuthor,
            sourcePublishedAt: note.sourcePublishedAt,
            sourceKind: note.sourceKind,
            sourceReferences: note.sourceReferences,
            savedAt: savedAt
        )
    }

    private static func revision(
        title: String,
        explanation: String,
        formattedExplanation: Data?,
        isDraft: Bool,
        draftText: String,
        sourceTitle: String,
        sourceURL: String?,
        sourceAuthor: String?,
        sourcePublishedAt: Date?,
        sourceKind: String?,
        sourceReferences: [String],
        savedAt: Date
    ) -> KnowledgeNoteRevision {
        KnowledgeNoteRevision(
            savedAt: savedAt,
            title: title,
            explanation: explanation,
            formattedExplanation: formattedExplanation,
            isDraft: isDraft,
            draftText: draftText,
            sourceTitle: sourceTitle,
            sourceURL: sourceURL,
            sourceAuthor: sourceAuthor,
            sourcePublishedAt: sourcePublishedAt,
            sourceKind: sourceKind,
            sourceReferences: sourceReferences
        )
    }
}
