import Foundation
#if os(iOS)
import WidgetKit
#endif

struct CurrentArticleSnapshot: Codable, Sendable {
    let id: UUID
    let title: String
    let source: String
    let readingMinutes: Int
    let publishedAt: Date
}

nonisolated enum WidgetSnapshotStore {
    static let suiteName = "group.felix.MonoRss"
    static let key = "currentArticleSnapshot"

    static func write(article: Article?) {
        #if os(iOS)
        let defaults = UserDefaults(suiteName: suiteName)
        if let article {
            let snapshot = CurrentArticleSnapshot(
                id: article.id,
                title: article.title,
                source: article.feed?.title ?? "OneFeed",
                readingMinutes: article.resolvedReadingMinutes,
                publishedAt: article.publishedAt
            )
            defaults?.set(try? JSONEncoder().encode(snapshot), forKey: key)
        } else {
            defaults?.removeObject(forKey: key)
        }
        Task { @MainActor in
            WidgetCenter.shared.reloadTimelines(ofKind: "CurrentArticleWidget")
        }
        #endif
    }
}
