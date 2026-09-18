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
    /// 0 is unrated; 1 through 5 are stars.
    var rating: Int = 0
    var aiSummary: String?
    var declinedVideoSummary: Bool = false
    /// Bumped only on user-facing state changes (read / skip / save / current).
    /// Fresh RSS inserts stay at `.distantPast` so another device’s reading
    /// state wins on first merge.
    var libraryUpdatedAt: Date = Date.distantPast
    var feed: Feed?

    var state: ArticleState {
        get { ArticleState(rawValue: stateRawValue) ?? .queued }
        set { stateRawValue = newValue.rawValue }
    }

    var kindLabel: String? {
        switch contentKind {
        case "youtube": "Video"
        case "podcast": "Podcast"
        case "music": "Music"
        default: nil
        }
    }

    /// Stored estimate. Lists must not regex `contentHTML` in `body`.
    var resolvedReadingMinutes: Int {
        estimatedReadingMinutes
    }

    /// Timed length when known. Videos without a fetched duration return nil
    /// instead of a fake "1 min". Articles omit "1 min read" until the body is
    /// long enough to be a real estimate, not an RSS teaser.
    var timedDurationPhrase: String? {
        if durationSeconds >= 60 {
            let minutes = max(1, Int((Double(durationSeconds) / 60.0).rounded()))
            return "\(minutes) min"
        }
        if durationSeconds > 0 {
            return "\(durationSeconds) sec"
        }
        if contentKind == "article" {
            let minutes = estimatedReadingMinutes
            guard minutes >= 2 else { return nil }
            return "\(minutes) min read"
        }
        return nil
    }

    var durationPhrase: String {
        timedDurationPhrase ?? kindLabel ?? ""
    }

    /// Raises the persisted estimate when current HTML is longer than ingest.
    func refreshEstimatedReadingMinutes() {
        guard contentKind == "article" else { return }
        let minutes = ContentClassifier.readingMinutes(
            words: ContentClassifier.wordCount(in: contentHTML ?? summary ?? "")
        )
        if minutes > estimatedReadingMinutes {
            estimatedReadingMinutes = minutes
        }
    }

    var readableHTML: String? {
        let value = contentHTML ?? summary
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    var displayImageURL: URL? { FeedImageURL.displayable(imageURL) }

    var displayExcerpt: String? {
        if let aiSummary {
            let plain = ContentClassifier.plainExcerpt(aiSummary, maxCharacters: 280)
            if !plain.isEmpty { return plain }
        }
        guard let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let plain = ContentClassifier.plainExcerpt(summary)
        return plain.isEmpty ? nil : plain
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
        rating: Int = 0,
        aiSummary: String? = nil,
        declinedVideoSummary: Bool = false,
        libraryUpdatedAt: Date = .distantPast,
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
        self.rating = min(5, max(0, rating))
        self.aiSummary = aiSummary
        self.declinedVideoSummary = declinedVideoSummary
        self.libraryUpdatedAt = libraryUpdatedAt
        self.feed = feed
    }

    func touchLibrary() {
        libraryUpdatedAt = .now
    }

    func setRating(_ value: Int) {
        rating = min(5, max(0, value))
    }

    /// SwiftData fatals if persisted properties are read after the row is gone.
    var isStored: Bool { modelContext != nil }
}
