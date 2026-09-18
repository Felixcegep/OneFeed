import Foundation
import Observation
import SwiftData

struct HistoryDay: Identifiable {
    let day: Date
    let label: String
    let articles: [Article]
    var id: Date { day }
}

enum HistoryViewModel {
    static func days(from articles: [Article]) -> [HistoryDay] {
        let calendar = Calendar.current
        let stored = articles.filter(\.isStored)
        let groups = Dictionary(grouping: stored) { calendar.startOfDay(for: $0.completedAt ?? $0.publishedAt) }
        return groups.keys.sorted(by: >).map { day in
            let label: String
            if calendar.isDateInToday(day) { label = "Today" }
            else if calendar.isDateInYesterday(day) { label = "Yesterday" }
            else { label = day.formatted(.dateTime.month(.abbreviated).day()) }
            return HistoryDay(day: day, label: label, articles: groups[day] ?? [])
        }
    }
}
