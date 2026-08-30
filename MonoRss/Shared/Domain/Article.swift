import Foundation
import SwiftData

enum ArticleState: String, Codable, CaseIterable, Sendable {
    case queued
    case current
    case read
    case skipped
    case saved
}

@Model
final class Article {
    @Attribute(.unique) var id: UUID
    var guid: String
    var title: String
    var url: URL?
    var author: String?
    var publishedAt: Date
    var summary: String?
    var contentHTML: String?
    var estimatedReadingMinutes: Int
    var stateRawValue: String
    var firstDisplayedAt: Date?
    var completedAt: Date?
    var remoteID: String?
    var isRemoteStarred: Bool
    var feed: Feed?

    var state: ArticleState {
        get { ArticleState(rawValue: stateRawValue) ?? .queued }
        set { stateRawValue = newValue.rawValue }
    }

    var readableHTML: String? {
        let value = contentHTML ?? summary
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    init(
        id: UUID = UUID(),
        guid: String,
        title: String,
        url: URL? = nil,
        author: String? = nil,
        publishedAt: Date = .now,
        summary: String? = nil,
        contentHTML: String? = nil,
        estimatedReadingMinutes: Int = 1,
        state: ArticleState = .queued,
        remoteID: String? = nil,
        isRemoteStarred: Bool = false,
        feed: Feed? = nil
    ) {
        self.id = id
        self.guid = guid
        self.title = title
        self.url = url
        self.author = author
        self.publishedAt = publishedAt
        self.summary = summary
        self.contentHTML = contentHTML
        self.estimatedReadingMinutes = max(1, estimatedReadingMinutes)
        self.stateRawValue = state.rawValue
        self.remoteID = remoteID
        self.isRemoteStarred = isRemoteStarred
        self.feed = feed
    }
}
