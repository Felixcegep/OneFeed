import Foundation
import SwiftData

@Model
final class Feed {
    @Attribute(.unique) var id: UUID
    var title: String
    var websiteURL: URL?
    var feedURL: URL
    var isEnabled: Bool
    var lastFetchedAt: Date?
    var etag: String?
    var lastModified: String?
    var remoteID: String?
    /// GReader/FreshRSS folder label, for example `Philosophy`. Nil means unfiled.
    var folderName: String?
    /// `article`, `youtube`, `music`, or `podcast` refresh over RSS.
    /// `pdf`, `epub`, and `page` are imported once and read locally.
    var contentKind: String = "article"
    var includeInToday: Bool = true
    var includeVideos: Bool = true
    var includeShorts: Bool = false
    var minVideoSeconds: Int = 180
    var blockedWords: String = ""
    /// Bumped only when the user changes subscription metadata, so RSS fetches
    /// cannot overwrite a newer library file from another device.
    var libraryUpdatedAt: Date = Date.distantPast

    @Relationship(deleteRule: .cascade, inverse: \Article.feed)
    var articles: [Article] = []

    init(
        id: UUID = UUID(),
        title: String,
        websiteURL: URL? = nil,
        feedURL: URL,
        isEnabled: Bool = true,
        lastFetchedAt: Date? = nil,
        etag: String? = nil,
        lastModified: String? = nil,
        remoteID: String? = nil,
        folderName: String? = nil,
        contentKind: String = "article",
        includeInToday: Bool = true,
        includeVideos: Bool = true,
        includeShorts: Bool = false,
        minVideoSeconds: Int = 180,
        blockedWords: String = "",
        libraryUpdatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.websiteURL = websiteURL
        self.feedURL = feedURL
        self.isEnabled = isEnabled
        self.lastFetchedAt = lastFetchedAt
        self.etag = etag
        self.lastModified = lastModified
        self.remoteID = remoteID
        self.folderName = folderName
        self.contentKind = contentKind
        self.includeInToday = includeInToday
        self.includeVideos = includeVideos
        self.includeShorts = includeShorts
        self.minVideoSeconds = minVideoSeconds
        self.blockedWords = blockedWords
        self.libraryUpdatedAt = libraryUpdatedAt
    }

    func touchLibrary() {
        libraryUpdatedAt = .now
    }

    /// RSS and Atom subscriptions refresh in place. A PDF, EPUB, or single page is imported once.
    var refreshesOverRSS: Bool {
        switch contentKind {
        case "pdf", "epub", "page": false
        default: true
        }
    }
}
