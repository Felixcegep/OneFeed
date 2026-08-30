import SwiftUI
import WidgetKit

private struct CurrentArticleSnapshot: Codable {
    let id: UUID
    let title: String
    let source: String
    let readingMinutes: Int
    let publishedAt: Date
}

private struct CurrentArticleEntry: TimelineEntry {
    let date: Date
    let article: CurrentArticleSnapshot?
}

private struct CurrentArticleProvider: TimelineProvider {
    func placeholder(in context: Context) -> CurrentArticleEntry {
        CurrentArticleEntry(date: .now, article: .init(id: UUID(), title: "One article at a time", source: "ONEFEED", readingMinutes: 6, publishedAt: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (CurrentArticleEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CurrentArticleEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(30 * 60))))
    }

    private func entry() -> CurrentArticleEntry {
        let defaults = UserDefaults(suiteName: "group.felix.MonoRss")
        let article = defaults?.data(forKey: "currentArticleSnapshot").flatMap { try? JSONDecoder().decode(CurrentArticleSnapshot.self, from: $0) }
        return CurrentArticleEntry(date: .now, article: article)
    }
}

private struct CurrentArticleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CurrentArticleEntry

    var body: some View {
        Group {
            if let article = entry.article {
                VStack(alignment: .leading, spacing: 8) {
                    Text("NEXT")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.1)
                        .foregroundStyle(.secondary)
                    if family == .accessoryInline {
                        Text("Next · \(article.readingMinutes) min")
                    } else {
                        Text(article.title)
                            .font(.headline)
                            .lineLimit(family == .systemSmall ? 3 : 4)
                        Spacer(minLength: 0)
                        Text("\(article.source) · \(article.readingMinutes) min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .widgetURL(URL(string: "onefeed://reader/\(article.id.uuidString)"))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "checkmark.circle")
                    Text("You’re caught up.")
                        .font(.headline)
                }
            }
        }
        .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
    }
}

struct CurrentArticleWidget: Widget {
    let kind = "CurrentArticleWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CurrentArticleProvider()) { entry in CurrentArticleWidgetView(entry: entry) }
            .configurationDisplayName("Next Article")
            .description("Keep your one current article close by.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryRectangular])
    }
}

@main
struct MonoRssWidgetBundle: WidgetBundle {
    var body: some Widget { CurrentArticleWidget() }
}
