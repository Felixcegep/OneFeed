import Foundation
import SwiftData

enum ArticleState: String, Codable, CaseIterable, Sendable {
    case queued
    case current
    case read
    case skipped
    case saved
}

nonisolated enum ArticleReadingReaction: String, CaseIterable, Codable, Sendable {
    case learned, why, connect, use

    var label: String {
        switch self {
        case .learned: String(localized: "Learned")
        case .why: String(localized: "Why")
        case .connect: String(localized: "Connect")
        case .use: String(localized: "Use")
        }
    }

    var prompt: String {
        switch self {
        case .learned: String(localized: "What is the one idea you want to remember?")
        case .why: String(localized: "Why does that make sense?")
        case .connect: String(localized: "What does this remind you of?")
        case .use: String(localized: "What will you do with this?")
        }
    }

    var glyph: String {
        switch self {
        case .learned: "\u{1F4A1}"
        case .why: "\u{1F914}"
        case .connect: "\u{1F517}"
        case .use: "\u{1F4CC}"
        }
    }

    /// Empty or unknown raw values are none.
    static func clampedRawValue(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let reaction = ArticleReadingReaction(rawValue: trimmed) else { return "" }
        return reaction.rawValue
    }

    init?(stored raw: String) {
        let clamped = Self.clampedRawValue(raw)
        guard !clamped.isEmpty else { return nil }
        self.init(rawValue: clamped)
    }
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
    /// Taste signal. The article is also skipped so it leaves Today and Feed.
    var notInterested: Bool = false
    var aiSummary: String?
    var declinedVideoSummary: Bool = false
    var videoChatJSON: Data? = nil
    var videoGeminiInteractionID: String? = nil
    /// Bumped only on user-facing state changes (read / skip / save / current).
    /// Fresh RSS inserts stay at `.distantPast` so another device’s reading
    /// state wins on first merge.
    var libraryUpdatedAt: Date = Date.distantPast
    var readingReactionRawValue: String = ""
    var readingNote: String = ""
    var feed: Feed?

    var state: ArticleState {
        get { ArticleState(rawValue: stateRawValue) ?? .queued }
        set { stateRawValue = newValue.rawValue }
    }

    var isCurrentReading: Bool { state == .current }

    var currentReadingLabel: String? {
        isCurrentReading ? String(localized: "Now reading") : nil
    }

    var historyStatus: String {
        if notInterested { return String(localized: "Not interested") }
        return state == .read ? String(localized: "Read") : String(localized: "Skipped")
    }

    var kindLabel: String? {
        switch contentKind {
        case "youtube": "Video"
        case "podcast": "Podcast"
        case "music": "Music"
        case "pdf": "PDF"
        case "epub": "Book"
        default: nil
        }
    }

    var isImportedDocument: Bool {
        contentKind == "pdf" || contentKind == "epub"
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
        if contentKind == "article" || isImportedDocument {
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

    /// The reader asks for this on redraws. Trimming the stored body once is enough.
    @Transient private var cachedReadableSource: String?
    @Transient private var cachedReadableHTML: String?

    var readableHTML: String? {
        let value = contentHTML ?? summary
        if cachedReadableSource == value { return cachedReadableHTML }
        cachedReadableSource = value
        guard let value else {
            cachedReadableHTML = nil
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        cachedReadableHTML = trimmed.isEmpty ? nil : value
        return cachedReadableHTML
    }

    var displayImageURL: URL? { FeedImageURL.displayable(imageURL) }

    /// Last plain excerpt for this instance. Lists redraw often; the HTML strip should not.
    @Transient private var cachedExcerptSource: String?
    @Transient private var cachedExcerptLimit: Int?
    @Transient private var cachedExcerpt: String?

    var displayExcerpt: String? {
        let source: String
        let limit: Int
        if let aiSummary, !aiSummary.isEmpty {
            source = aiSummary
            limit = 280
        } else if let summary, !summary.isEmpty {
            source = summary
            limit = 220
        } else {
            return nil
        }
        if cachedExcerptSource == source, cachedExcerptLimit == limit {
            return cachedExcerpt
        }
        let value = ContentClassifier.proseExcerpt(source, maxCharacters: limit)
        cachedExcerptSource = source
        cachedExcerptLimit = limit
        cachedExcerpt = value
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
        rating: Int = 0,
        notInterested: Bool = false,
        aiSummary: String? = nil,
        declinedVideoSummary: Bool = false,
        videoChatJSON: Data? = nil,
        videoGeminiInteractionID: String? = nil,
        libraryUpdatedAt: Date = .distantPast,
        readingReactionRawValue: String = "",
        readingNote: String = "",
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
        self.notInterested = notInterested
        self.aiSummary = aiSummary
        self.declinedVideoSummary = declinedVideoSummary
        self.videoChatJSON = videoChatJSON
        self.videoGeminiInteractionID = videoGeminiInteractionID
        self.libraryUpdatedAt = libraryUpdatedAt
        self.readingReactionRawValue = readingReactionRawValue
        self.readingNote = readingNote
        self.feed = feed
    }

    func touchLibrary() {
        libraryUpdatedAt = .now
    }

    func setRating(_ value: Int) {
        rating = min(5, max(0, value))
    }

    var readingReaction: ArticleReadingReaction? {
        get { ArticleReadingReaction(stored: readingReactionRawValue) }
        set { readingReactionRawValue = newValue?.rawValue ?? "" }
    }

    var readingNoteText: String {
        readingNote.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Choice word, then the sentence. Nil when both are empty.
    var readingTakeawayLine: String? {
        let note = readingNoteText
        switch (readingReaction?.label, note.isEmpty) {
        case (nil, true): return nil
        case let (label?, true): return label
        case (nil, false): return note
        case let (label?, false): return "\(label) \u{00B7} \(note)"
        }
    }

    func setReadingTakeaway(reaction: ArticleReadingReaction?, note: String) {
        readingReaction = reaction
        readingNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// SwiftData fatals if persisted properties are read after the row is gone.
    var isStored: Bool { modelContext != nil }
}
