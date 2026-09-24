import Foundation
import SwiftData

/// Drops old stories so the on-device library stays small.
/// Unread stories older than the period are removed, along with read and skipped
/// stories that have no takeaway. Queue, today's stack, and stories with a
/// takeaway stay.
@MainActor
struct ArticleRetentionService {
    nonisolated static let defaultRetentionDays = 7
    nonisolated static let firstImportDays = 7

    nonisolated static var configuredDays: Int {
        guard UserDefaults.standard.object(forKey: AppPreferenceKey.articleRetentionDays) != nil else {
            return defaultRetentionDays
        }
        return UserDefaults.standard.integer(forKey: AppPreferenceKey.articleRetentionDays)
    }

    /// First fetch of a feed only keeps the last week. Later fetches follow the library setting.
    nonisolated static func ingestCutoff(isFirstPopulate: Bool, now: Date = .now) -> Date? {
        let days: Int
        if isFirstPopulate {
            days = firstImportDays
        } else {
            days = configuredDays
        }
        guard days > 0 else { return nil }
        return now.addingTimeInterval(-TimeInterval(days) * 86_400)
    }

    @discardableResult
    func purge(in context: ModelContext, olderThanDays days: Int? = nil, now: Date = .now, persist: Bool = true) throws -> Int {
        try Self.purge(in: context, olderThanDays: days, now: now, persist: persist)
    }

    @discardableResult
    nonisolated static func purge(in context: ModelContext, olderThanDays days: Int? = nil, now: Date = .now, persist: Bool = true) throws -> Int {
        let days = days ?? Self.configuredDays
        guard days > 0 else { return 0 }
        let cutoff = now.addingTimeInterval(-TimeInterval(days) * 86_400)
        let saved = ArticleState.saved.rawValue
        let keptIDs = Set((try context.fetch(FetchDescriptor<DailyDeckItem>())).compactMap { $0.resolvedArticleID() })
        var descriptor = FetchDescriptor<Article>(predicate: #Predicate { article in
            article.publishedAt < cutoff && article.stateRawValue != saved && article.isRemoteStarred == false
        })
        // A takeaway and an imported file are enough to decide. The article body stays on disk.
        descriptor.propertiesToFetch = [
            \.id, \.guid, \.publishedAt, \.stateRawValue, \.isRemoteStarred,
            \.readingNote, \.readingReactionRawValue, \.contentKind, \.enclosureURL,
        ]
        let candidates = try context.fetch(descriptor)
        var removed = 0
        for article in candidates {
            if keptIDs.contains(article.id) { continue }
            if Self.hasTakeaway(article) { continue }
            if article.isImportedDocument {
                ImportedDocumentStore.shared.removeFiles(for: article)
            }
            context.delete(article)
            removed += 1
        }
        if persist, removed > 0 { try context.save() }
        return removed
    }

    /// A note or a reaction is a takeaway. Whitespace-only notes do not count.
    nonisolated private static func hasTakeaway(_ article: Article) -> Bool {
        !article.readingNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !article.readingReactionRawValue.isEmpty
    }
}
