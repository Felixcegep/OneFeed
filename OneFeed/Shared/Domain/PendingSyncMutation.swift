import Foundation
import SwiftData

@Model
final class PendingSyncMutation {
    @Attribute(.unique) var id: UUID
    var remoteArticleID: String
    var kindRawValue: String
    var createdAt: Date
    var attempts: Int

    var kind: FreshRSSMutationKind? { FreshRSSMutationKind(rawValue: kindRawValue) }

    init(id: UUID = UUID(), remoteArticleID: String, kind: FreshRSSMutationKind, createdAt: Date = .now) {
        self.id = id
        self.remoteArticleID = remoteArticleID
        self.kindRawValue = kind.rawValue
        self.createdAt = createdAt
        self.attempts = 0
    }
}
