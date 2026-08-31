import Foundation
import SwiftData
@testable import MonoRss

enum InMemoryStore {
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Feed.self, Article.self, SyncAccount.self, PendingSyncMutation.self,
            DailyDeck.self, DailyDeckItem.self,
        ])
        let configuration = ModelConfiguration(
            UUID().uuidString,
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func makeContext() throws -> ModelContext {
        ModelContext(try makeContainer())
    }
}
