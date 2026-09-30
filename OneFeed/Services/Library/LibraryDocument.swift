import Foundation

nonisolated enum LibraryDocumentFormat {
    static let schemaVersion = 3
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
    var knowledgeNotes: [LibraryKnowledgeNote]
    var currentArticleKey: String?
    var currentUpdatedAt: Date?

    init(
        schemaVersion: Int,
        updatedAt: Date,
        folderNames: [String],
        feeds: [LibraryFeed],
        articles: [LibraryArticle],
        tombstones: [LibraryTombstone],
        knowledgeNotes: [LibraryKnowledgeNote] = [],
        currentArticleKey: String?,
        currentUpdatedAt: Date?
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.folderNames = folderNames
        self.feeds = feeds
        self.articles = articles
        self.tombstones = tombstones
        self.knowledgeNotes = knowledgeNotes
        self.currentArticleKey = currentArticleKey
        self.currentUpdatedAt = currentUpdatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, updatedAt, folderNames, feeds, articles, tombstones
        case knowledgeNotes, currentArticleKey, currentUpdatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        folderNames = try container.decode([String].self, forKey: .folderNames)
        feeds = try container.decode([LibraryFeed].self, forKey: .feeds)
        articles = try container.decode([LibraryArticle].self, forKey: .articles)
        tombstones = try container.decode([LibraryTombstone].self, forKey: .tombstones)
        knowledgeNotes = try container.decodeIfPresent([LibraryKnowledgeNote].self, forKey: .knowledgeNotes) ?? []
        currentArticleKey = try container.decodeIfPresent(String.self, forKey: .currentArticleKey)
        currentUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .currentUpdatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(folderNames, forKey: .folderNames)
        try container.encode(feeds, forKey: .feeds)
        try container.encode(articles, forKey: .articles)
        try container.encode(tombstones, forKey: .tombstones)
        try container.encode(knowledgeNotes, forKey: .knowledgeNotes)
        try container.encodeIfPresent(currentArticleKey, forKey: .currentArticleKey)
        try container.encodeIfPresent(currentUpdatedAt, forKey: .currentUpdatedAt)
    }

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

nonisolated struct LibraryKnowledgeNote: Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var explanation: String
    var formattedExplanation: Data?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var isDraft: Bool
    var draftText: String
    var sourceArticleID: UUID?
    var sourceTitle: String
    var sourceURL: String?
    var sourceAuthor: String?
    var sourcePublishedAt: Date?
    var sourceKind: String?
    var sourceReferences: [String]
    var revisionHistory: Data?

    init(
        id: UUID,
        title: String,
        explanation: String,
        formattedExplanation: Data? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        isDraft: Bool = false,
        draftText: String = "",
        sourceArticleID: UUID? = nil,
        sourceTitle: String = "",
        sourceURL: String? = nil,
        sourceAuthor: String? = nil,
        sourcePublishedAt: Date? = nil,
        sourceKind: String? = nil,
        sourceReferences: [String] = [],
        revisionHistory: Data? = nil
    ) {
        self.id = id
        self.title = title
        self.explanation = explanation
        self.formattedExplanation = formattedExplanation
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.isDraft = isDraft
        self.draftText = draftText
        self.sourceArticleID = sourceArticleID
        self.sourceTitle = sourceTitle
        self.sourceURL = sourceURL
        self.sourceAuthor = sourceAuthor
        self.sourcePublishedAt = sourcePublishedAt
        self.sourceKind = sourceKind
        self.sourceReferences = sourceReferences
        self.revisionHistory = revisionHistory
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, explanation, formattedExplanation, createdAt, updatedAt, deletedAt
        case isDraft, draftText, sourceArticleID, sourceTitle, sourceURL, sourceAuthor
        case sourcePublishedAt, sourceKind, sourceReferences, revisionHistory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        explanation = try container.decode(String.self, forKey: .explanation)
        formattedExplanation = try container.decodeIfPresent(Data.self, forKey: .formattedExplanation)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        isDraft = try container.decodeIfPresent(Bool.self, forKey: .isDraft) ?? false
        draftText = try container.decodeIfPresent(String.self, forKey: .draftText) ?? ""
        sourceArticleID = try container.decodeIfPresent(UUID.self, forKey: .sourceArticleID)
        sourceTitle = try container.decodeIfPresent(String.self, forKey: .sourceTitle) ?? ""
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        sourceAuthor = try container.decodeIfPresent(String.self, forKey: .sourceAuthor)
        sourcePublishedAt = try container.decodeIfPresent(Date.self, forKey: .sourcePublishedAt)
        sourceKind = try container.decodeIfPresent(String.self, forKey: .sourceKind)
        sourceReferences = try container.decodeIfPresent([String].self, forKey: .sourceReferences) ?? []
        revisionHistory = try container.decodeIfPresent(Data.self, forKey: .revisionHistory)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(explanation, forKey: .explanation)
        try container.encodeIfPresent(formattedExplanation, forKey: .formattedExplanation)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(isDraft, forKey: .isDraft)
        try container.encode(draftText, forKey: .draftText)
        try container.encodeIfPresent(sourceArticleID, forKey: .sourceArticleID)
        try container.encode(sourceTitle, forKey: .sourceTitle)
        try container.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try container.encodeIfPresent(sourceAuthor, forKey: .sourceAuthor)
        try container.encodeIfPresent(sourcePublishedAt, forKey: .sourcePublishedAt)
        try container.encodeIfPresent(sourceKind, forKey: .sourceKind)
        try container.encode(sourceReferences, forKey: .sourceReferences)
        try container.encodeIfPresent(revisionHistory, forKey: .revisionHistory)
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
