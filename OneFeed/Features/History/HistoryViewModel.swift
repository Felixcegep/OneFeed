import Foundation
import Observation
import SwiftData

struct HistoryDay: Identifiable {
    let day: Date
    let label: String
    let articles: [Article]
    var id: Date { day }
}

struct HistoryStorySnap: Sendable {
    var id: UUID
    var completedAt: Date?
    var publishedAt: Date
    var title: String
    var readingNote: String
    var reactionRaw: String
    var feedTitle: String?
    var url: URL?
    var author: String?
    var contentKind: String
}

struct HistoryDayPlan: Sendable, Identifiable {
    var day: Date
    var articleIDs: [UUID]
    var id: Date { day }
}

enum HistoryViewModel {
    /// A modest history can be grouped on the open screen. A long one waits for the off-screen plan.
    static let synchronousGroupingLimit = 200

    static func groupsOnTheOpenScreen(storyCount: Int, isSearching: Bool) -> Bool {
        !isSearching && storyCount > 0 && storyCount <= synchronousGroupingLimit
    }

    static func days(from articles: [Article]) -> [HistoryDay] {
        let calendar = Calendar.current
        let stored = articles.filter(\.isStored)
        let groups = Dictionary(grouping: stored) { calendar.startOfDay(for: $0.completedAt ?? $0.publishedAt) }
        return groups.keys.sorted(by: >).map { day in
            let label = OneFeedDateLabel.historySection(day, calendar: calendar)
            let articles = (groups[day] ?? []).sorted {
                ($0.completedAt ?? $0.publishedAt) > ($1.completedAt ?? $1.publishedAt)
            }
            return HistoryDay(day: day, label: label, articles: articles)
        }
    }

    /// Groups copied history rows. Day labels stay on the main thread; there is one per day, not one per story.
    nonisolated static func dayPlans(from stories: [HistoryStorySnap], query: String, calendar: Calendar = .current) -> [HistoryDayPlan] {
        let matched = query.isEmpty ? stories : stories.filter { matches($0, query: query) }
        let groups = Dictionary(grouping: matched) { calendar.startOfDay(for: $0.completedAt ?? $0.publishedAt) }
        return groups.keys.sorted(by: >).map { day in
            let ids = (groups[day] ?? []).sorted {
                ($0.completedAt ?? $0.publishedAt) > ($1.completedAt ?? $1.publishedAt)
            }.map(\.id)
            return HistoryDayPlan(day: day, articleIDs: ids)
        }
    }

    nonisolated private static func matches(_ story: HistoryStorySnap, query: String) -> Bool {
        if story.title.localizedStandardContains(query) { return true }
        if story.readingNote.localizedStandardContains(query) { return true }
        if takeaway(story)?.localizedStandardContains(query) == true { return true }
        let source = ArticlePresentation.sourceName(
            feedTitle: story.feedTitle,
            url: story.url,
            author: story.author,
            contentKind: story.contentKind
        )
        return source.localizedStandardContains(query)
    }

    nonisolated private static func takeaway(_ story: HistoryStorySnap) -> String? {
        let note = story.readingNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = ArticleReadingReaction(stored: story.reactionRaw)?.label
        switch (label, note.isEmpty) {
        case (nil, true): return nil
        case let (label?, true): return label
        case (nil, false): return note
        case let (label?, false): return "\(label) \u{00B7} \(note)"
        }
    }
}
