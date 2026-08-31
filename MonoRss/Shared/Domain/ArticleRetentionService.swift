import Foundation
import SwiftData

/// Drops old unread/unkept articles so the on-device library stays small.
/// Saved (starred) items and anything in today's stack are never purged.
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
    func purge(in context: ModelContext, olderThanDays days: Int? = nil, now: Date = .now) throws -> Int {
        let days = days ?? Self.configuredDays
        guard days > 0 else { return 0 }
        let cutoff = now.addingTimeInterval(-TimeInterval(days) * 86_400)
        let saved = ArticleState.saved.rawValue
        let keptIDs = Set((try context.fetch(FetchDescriptor<DailyDeckItem>())).compactMap(\.article?.id))
        let articles = try context.fetch(FetchDescriptor<Article>())
        var removed = 0
        for article in articles {
            if article.stateRawValue == saved || article.isRemoteStarred { continue }
            if keptIDs.contains(article.id) { continue }
            if article.publishedAt >= cutoff { continue }
            context.delete(article)
            removed += 1
        }
        if removed > 0 { try context.save() }
        return removed
    }
}
