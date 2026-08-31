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
    var contentKind: String = "article"
    var durationSeconds: Int = 0
    var imageURL: URL?
    var videoID: String?
    var enclosureURL: URL?
    var enclosureMIME: String?
    var feed: Feed?

    var state: ArticleState {
        get { ArticleState(rawValue: stateRawValue) ?? .queued }
        set { stateRawValue = newValue.rawValue }
    }

    var durationPhrase: String {
        switch contentKind {
        case "youtube", "podcast", "music":
            return "\(estimatedReadingMinutes) min"
        default:
            return "\(estimatedReadingMinutes) min read"
        }
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
        contentKind: String = "article",
        durationSeconds: Int = 0,
        imageURL: URL? = nil,
        videoID: String? = nil,
        enclosureURL: URL? = nil,
        enclosureMIME: String? = nil,
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
        self.contentKind = contentKind
        self.durationSeconds = max(0, durationSeconds)
        self.imageURL = imageURL
        self.videoID = videoID
        self.enclosureURL = enclosureURL
        self.enclosureMIME = enclosureMIME
        self.feed = feed
    }
}
