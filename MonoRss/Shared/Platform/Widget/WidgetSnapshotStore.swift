import Foundation
import WidgetKit

struct CurrentArticleSnapshot: Codable, Sendable {
    let id: UUID
    let title: String
    let source: String
    let readingMinutes: Int
    let publishedAt: Date
}

enum WidgetSnapshotStore {
    static let suiteName = "group.felix.MonoRss"
    static let key = "currentArticleSnapshot"

    static func write(article: Article?) {
        let defaults = UserDefaults(suiteName: suiteName)
        if let article {
            let snapshot = CurrentArticleSnapshot(
                id: article.id,
                title: article.title,
                source: article.feed?.title ?? "OneFeed",
                readingMinutes: article.estimatedReadingMinutes,
                publishedAt: article.publishedAt
            )
            defaults?.set(try? JSONEncoder().encode(snapshot), forKey: key)
        } else {
            defaults?.removeObject(forKey: key)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "CurrentArticleWidget")
    }
}
