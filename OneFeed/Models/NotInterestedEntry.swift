import Foundation
import SwiftData

@Model
final class NotInterestedEntry {
    @Attribute(.unique) var id: UUID
    var recordedAt: Date
    var articleTitle: String
    var articleURL: String?
    var articleGUID: String
    var sourceTitle: String
    var sourceFeedURL: String
    var sourceWebsiteURL: String?
    var feedID: UUID?

    init(
        id: UUID = UUID(),
        recordedAt: Date = .now,
        articleTitle: String,
        articleURL: String? = nil,
        articleGUID: String,
        sourceTitle: String,
        sourceFeedURL: String,
        sourceWebsiteURL: String? = nil,
        feedID: UUID? = nil
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.articleTitle = articleTitle
        self.articleURL = articleURL
        self.articleGUID = articleGUID
        self.sourceTitle = sourceTitle
        self.sourceFeedURL = sourceFeedURL
        self.sourceWebsiteURL = sourceWebsiteURL
        self.feedID = feedID
    }
}

struct NotInterestedSourceGroup: Identifiable {
    var id: String { sourceFeedURL }
    let sourceTitle: String
    let sourceFeedURL: String
    let sourceWebsiteURL: String?
    let feedID: UUID?
    let entries: [NotInterestedEntry]

    var count: Int { entries.count }
}
