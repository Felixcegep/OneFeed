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
        folderName: String? = nil
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
    }
}
