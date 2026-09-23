import Foundation

nonisolated enum LibraryDocumentFormat {
    static let schemaVersion = 2
    static let fileName = "OneFeed.library.json"

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(LibraryJSON.string(from: date))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = LibraryJSON.date(from: raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid library date")
            }
            return date
        }
        return decoder
    }
}

nonisolated private enum LibraryJSON {
    static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let fallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from raw: String) -> Date? {
        formatter.date(from: raw) ?? fallbackFormatter.date(from: raw)
    }
}

nonisolated struct LibraryDocument: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var updatedAt: Date
    var folderNames: [String]
    var feeds: [LibraryFeed]
    var articles: [LibraryArticle]
    var tombstones: [LibraryTombstone]
    var currentArticleKey: String?
    var currentUpdatedAt: Date?

    static func empty(now: Date = .now) -> LibraryDocument {
        LibraryDocument(
            schemaVersion: LibraryDocumentFormat.schemaVersion,
            updatedAt: now,
            folderNames: [],
            feeds: [],
            articles: [],
            tombstones: [],
            currentArticleKey: nil,
            currentUpdatedAt: nil
        )
    }

    func encoded() throws -> Data {
        try LibraryDocumentFormat.encoder().encode(self)
    }

    static func decode(_ data: Data) throws -> LibraryDocument {
        try LibraryDocumentFormat.decoder().decode(LibraryDocument.self, from: data)
    }
}

nonisolated struct LibraryFeed: Codable, Equatable, Sendable {
    var feedURL: String
    var title: String
    var websiteURL: String?
    /// Primary folder. Older library files only have this field.
    var folderName: String?
    /// Every folder this source belongs to.
    var folderNames: [String]
    var isEnabled: Bool
    var contentKind: String
    var includeInToday: Bool
    var includeVideos: Bool
    var includeShorts: Bool
    var minVideoSeconds: Int
    var blockedWords: String
    var updatedAt: Date

    var resolvedFolderNames: [String] {
        let names = FeedMembership.normalize(folderNames)
        if !names.isEmpty { return names }
        if let legacy = FeedMembership.normalized(folderName) { return [legacy] }
        return []
    }

    init(
        feedURL: String,
        title: String,
        websiteURL: String?,
        folderName: String? = nil,
        folderNames: [String] = [],
        isEnabled: Bool,
        contentKind: String,
        includeInToday: Bool,
        includeVideos: Bool,
        includeShorts: Bool,
        minVideoSeconds: Int,
        blockedWords: String,
        updatedAt: Date
    ) {
        self.feedURL = feedURL
        self.title = title
        self.websiteURL = websiteURL
        let resolved = FeedMembership.normalize(
            folderNames.isEmpty
                ? (FeedMembership.normalized(folderName).map { [$0] } ?? [])
                : folderNames
        )
        self.folderNames = resolved
        self.folderName = resolved.first
        self.isEnabled = isEnabled
        self.contentKind = contentKind
        self.includeInToday = includeInToday
        self.includeVideos = includeVideos
        self.includeShorts = includeShorts
        self.minVideoSeconds = minVideoSeconds
        self.blockedWords = blockedWords
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case feedURL, title, websiteURL, folderName, folderNames, isEnabled, contentKind
        case includeInToday, includeVideos, includeShorts, minVideoSeconds, blockedWords, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        feedURL = try container.decode(String.self, forKey: .feedURL)
        title = try container.decode(String.self, forKey: .title)
        websiteURL = try container.decodeIfPresent(String.self, forKey: .websiteURL)
        let legacy = try container.decodeIfPresent(String.self, forKey: .folderName)
        let stored = try container.decodeIfPresent([String].self, forKey: .folderNames) ?? []
        let resolved = FeedMembership.normalize(
            stored.isEmpty ? (FeedMembership.normalized(legacy).map { [$0] } ?? []) : stored
        )
        folderNames = resolved
        folderName = resolved.first
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        contentKind = try container.decode(String.self, forKey: .contentKind)
        includeInToday = try container.decode(Bool.self, forKey: .includeInToday)
        includeVideos = try container.decode(Bool.self, forKey: .includeVideos)
        includeShorts = try container.decode(Bool.self, forKey: .includeShorts)
        minVideoSeconds = try container.decode(Int.self, forKey: .minVideoSeconds)
        blockedWords = try container.decode(String.self, forKey: .blockedWords)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(feedURL, forKey: .feedURL)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(websiteURL, forKey: .websiteURL)
        try container.encodeIfPresent(folderNames.first, forKey: .folderName)
        try container.encode(folderNames, forKey: .folderNames)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(contentKind, forKey: .contentKind)
        try container.encode(includeInToday, forKey: .includeInToday)
        try container.encode(includeVideos, forKey: .includeVideos)
        try container.encode(includeShorts, forKey: .includeShorts)
        try container.encode(minVideoSeconds, forKey: .minVideoSeconds)
        try container.encode(blockedWords, forKey: .blockedWords)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

nonisolated struct LibraryArticle: Codable, Equatable, Sendable {
    var key: String
    var feedURL: String
    var guid: String
    var title: String
    var url: String?
    var state: ArticleState
    var completedAt: Date?
    var isRemoteStarred: Bool
    var updatedAt: Date
    var readingReactionRawValue: String
    var readingNote: String

    init(
        key: String,
        feedURL: String,
        guid: String,
        title: String,
        url: String?,
        state: ArticleState,
        completedAt: Date?,
        isRemoteStarred: Bool,
        updatedAt: Date,
        readingReactionRawValue: String = "",
        readingNote: String = ""
    ) {
        self.key = key
        self.feedURL = feedURL
        self.guid = guid
        self.title = title
        self.url = url
        self.state = state
        self.completedAt = completedAt
        self.isRemoteStarred = isRemoteStarred
        self.updatedAt = updatedAt
        self.readingReactionRawValue = readingReactionRawValue
        self.readingNote = readingNote
    }

    enum CodingKeys: String, CodingKey {
        case key, feedURL, guid, title, url, state, completedAt, isRemoteStarred, updatedAt
        case readingReactionRawValue, readingNote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        feedURL = try container.decode(String.self, forKey: .feedURL)
        guid = try container.decode(String.self, forKey: .guid)
        title = try container.decode(String.self, forKey: .title)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        state = try container.decode(ArticleState.self, forKey: .state)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        isRemoteStarred = try container.decode(Bool.self, forKey: .isRemoteStarred)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        let storedReaction = try container.decodeIfPresent(String.self, forKey: .readingReactionRawValue) ?? ""
        readingReactionRawValue = ArticleReadingReaction.clampedRawValue(storedReaction)
        readingNote = try container.decodeIfPresent(String.self, forKey: .readingNote) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(feedURL, forKey: .feedURL)
        try container.encode(guid, forKey: .guid)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encode(isRemoteStarred, forKey: .isRemoteStarred)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(readingReactionRawValue, forKey: .readingReactionRawValue)
        try container.encode(readingNote, forKey: .readingNote)
    }
}

nonisolated struct LibraryTombstone: Codable, Equatable, Sendable {
    var feedURL: String
    var deletedAt: Date
}

nonisolated struct LibraryMergeOptions: Equatable, Sendable {
    var syncFeeds: Bool
    var syncReadAndSaved: Bool

    static let all = LibraryMergeOptions(syncFeeds: true, syncReadAndSaved: true)

    static func forAccount(freshRSSEnabled: Bool) -> LibraryMergeOptions {
        LibraryMergeOptions(syncFeeds: !freshRSSEnabled, syncReadAndSaved: !freshRSSEnabled)
    }

    func shouldApply(state: ArticleState) -> Bool {
        if syncReadAndSaved { return true }
        return state == .skipped || state == .current
    }
}
