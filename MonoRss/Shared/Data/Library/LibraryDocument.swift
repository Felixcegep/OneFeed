import Foundation

enum LibraryDocumentFormat {
    static let schemaVersion = 1
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

private enum LibraryJSON {
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

struct LibraryDocument: Codable, Equatable, Sendable {
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

struct LibraryFeed: Codable, Equatable, Sendable {
    var feedURL: String
    var title: String
    var websiteURL: String?
    var folderName: String?
    var isEnabled: Bool
    var contentKind: String
    var includeInToday: Bool
    var includeVideos: Bool
    var includeShorts: Bool
    var minVideoSeconds: Int
    var blockedWords: String
    var updatedAt: Date
}

struct LibraryArticle: Codable, Equatable, Sendable {
    var key: String
    var feedURL: String
    var guid: String
    var title: String
    var url: String?
    var state: ArticleState
    var completedAt: Date?
    var isRemoteStarred: Bool
    var updatedAt: Date
}

struct LibraryTombstone: Codable, Equatable, Sendable {
    var feedURL: String
    var deletedAt: Date
}

struct LibraryMergeOptions: Equatable, Sendable {
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
