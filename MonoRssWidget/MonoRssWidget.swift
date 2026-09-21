import SwiftUI
import WidgetKit
import UIKit

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

private struct WidgetPaper {
    /// Keep in sync with `OneFeedPalette.canvas` / `text` / `subdued`.
    static let cream = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.110, green: 0.106, blue: 0.094, alpha: 1)
            : UIColor(red: 0.953, green: 0.937, blue: 0.898, alpha: 1)
    })
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.953, green: 0.937, blue: 0.898, alpha: 1)
            : UIColor(red: 0.090, green: 0.090, blue: 0.082, alpha: 1)
    })
    static let stone = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.706, green: 0.690, blue: 0.655, alpha: 1)
            : UIColor(red: 0.384, green: 0.373, blue: 0.345, alpha: 1)
    })
}

private struct CurrentArticleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CurrentArticleEntry

    var body: some View {
        Group {
            if let article = entry.article {
                VStack(alignment: .leading, spacing: 8) {
                    Text("NEXT")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.4)
                        .textCase(.uppercase)
                        .foregroundStyle(WidgetPaper.stone)
                    if family == .accessoryInline {
                        Text("Next · \(article.readingMinutes) min")
                            .foregroundStyle(WidgetPaper.ink)
                    } else {
                        Text(article.title)
                            .font(.system(size: family == .systemSmall ? 15 : 17, weight: .regular, design: .serif))
                            .foregroundStyle(WidgetPaper.ink)
                            .lineLimit(family == .systemSmall ? 3 : 4)
                        Spacer(minLength: 0)
                        Text("\(article.source) · \(article.readingMinutes) min")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(WidgetPaper.stone)
                            .lineLimit(1)
                    }
                }
                .widgetURL(URL(string: "onefeed://reader/\(article.id.uuidString)"))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(WidgetPaper.stone)
                    Text("You’re caught up.")
                        .font(.system(size: 17, weight: .regular, design: .serif))
                        .foregroundStyle(WidgetPaper.ink)
                }
            }
        }
        .containerBackground(for: .widget) {
            if family == .accessoryInline || family == .accessoryRectangular {
                AccessoryWidgetBackground()
            } else {
                WidgetPaper.cream
            }
        }
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
