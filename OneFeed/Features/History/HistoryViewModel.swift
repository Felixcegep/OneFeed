import Foundation
import Observation
import SwiftData

struct HistoryDay: Identifiable {
    let day: Date
    let label: String
    let articles: [Article]
    var id: Date { day }
}

@MainActor
@Observable
final class HistoryViewModel {
    private(set) var days: [HistoryDay] = []

    func load(from context: ModelContext) {
        let read = ArticleState.read.rawValue
        let skipped = ArticleState.skipped.rawValue
        var descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.stateRawValue == read || $0.stateRawValue == skipped })
        descriptor.sortBy = [SortDescriptor(\.completedAt, order: .reverse)]
        let articles = (try? context.fetch(descriptor)) ?? []
        let calendar = Calendar.current
        let groups = Dictionary(grouping: articles) { calendar.startOfDay(for: $0.completedAt ?? $0.publishedAt) }
        days = groups.keys.sorted(by: >).map { day in
            let label: String
            if calendar.isDateInToday(day) { label = "TODAY" }
            else if calendar.isDateInYesterday(day) { label = "YESTERDAY" }
            else { label = day.formatted(.dateTime.month(.abbreviated).day()).uppercased() }
            return HistoryDay(day: day, label: label, articles: groups[day] ?? [])
        }
    }
}
