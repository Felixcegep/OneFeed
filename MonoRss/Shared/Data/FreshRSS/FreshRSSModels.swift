import Foundation

nonisolated public struct FreshRSSAuthResponse: Codable, Sendable, Equatable {
    public let authToken: String
    public let userName: String?

    public init(authToken: String, userName: String? = nil) {
        self.authToken = authToken
        self.userName = userName
    }
}

nonisolated public struct FreshRSSSubscriptionResponse: Codable, Sendable, Equatable {
    public let subscriptions: [FreshRSSSubscription]

    public init(subscriptions: [FreshRSSSubscription]) {
        self.subscriptions = subscriptions
    }
}

nonisolated public struct FreshRSSSubscription: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let feedURL: URL?
    public let htmlURL: URL?
    public let iconURL: URL?
    public let categories: [FreshRSSFolder]

    public init(id: String, title: String, feedURL: URL? = nil, htmlURL: URL? = nil, iconURL: URL? = nil, categories: [FreshRSSFolder] = []) {
        self.id = id
        self.title = title
        self.feedURL = feedURL
        self.htmlURL = htmlURL
        self.iconURL = iconURL
        self.categories = categories
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case feedURL = "url"
        case htmlURL = "htmlUrl"
        case iconURL = "iconUrl"
        case categories
    }

    public var folderName: String? {
        categories.first(where: \.isUserFolder)?.displayName
    }
}

nonisolated public struct FreshRSSFolder: Codable, Sendable, Equatable {
    public let id: String
    public let label: String?

    public init(id: String, label: String? = nil) {
        self.id = id
        self.label = label
    }

    public var isUserFolder: Bool {
        id.contains("/label/") && !id.contains("/state/com.google/")
    }

    public var displayName: String {
        if let label, !label.isEmpty { return label }
        guard let last = id.split(separator: "/").last else { return id }
        let raw = String(last)
        return raw.removingPercentEncoding ?? raw
    }
}

nonisolated public struct FreshRSSStreamItemIDsResponse: Codable, Sendable, Equatable {
    public let itemRefs: [FreshRSSItemReference]
    public let continuation: String?

    public init(itemRefs: [FreshRSSItemReference], continuation: String? = nil) {
        self.itemRefs = itemRefs
        self.continuation = continuation
    }
}

nonisolated public struct FreshRSSItemReference: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let timestampUsec: String?

    public init(id: String, timestampUsec: String? = nil) {
        self.id = id
        self.timestampUsec = timestampUsec
    }
}

nonisolated public struct FreshRSSStreamContentsResponse: Codable, Sendable, Equatable {
    public let direction: String?
    public let id: String?
    public let title: String?
    public let description: String?
    public let selfURL: URL?
    public let updatedUsec: String?
    public let continuation: String?
    public let items: [FreshRSSItem]

    public init(items: [FreshRSSItem], direction: String? = nil, id: String? = nil,
                title: String? = nil, description: String? = nil, selfURL: URL? = nil,
                updatedUsec: String? = nil, continuation: String? = nil) {
        self.items = items
        self.direction = direction
        self.id = id
        self.title = title
        self.description = description
        self.selfURL = selfURL
        self.updatedUsec = updatedUsec
        self.continuation = continuation
    }

    enum CodingKeys: String, CodingKey {
        case direction, id, title, description
        case selfURL = "self"
        case updatedUsec
        case continuation
        case items
    }
}

nonisolated public struct FreshRSSItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let crawlTimeMsec: String?
    public let timestampUsec: String?
    public let title: String
    public let author: FreshRSSAuthor?
    public let origin: FreshRSSOrigin?
    public let canonical: [FreshRSSLink]
    public let alternate: [FreshRSSLink]
    public let summary: FreshRSSContent?
    public let content: FreshRSSContent?
    public let categories: [String]

    public init(id: String, title: String, crawlTimeMsec: String? = nil,
                timestampUsec: String? = nil, author: FreshRSSAuthor? = nil,
                origin: FreshRSSOrigin? = nil, canonical: [FreshRSSLink] = [],
                alternate: [FreshRSSLink] = [], summary: FreshRSSContent? = nil,
                content: FreshRSSContent? = nil, categories: [String] = []) {
        self.id = id
        self.title = title
        self.crawlTimeMsec = crawlTimeMsec
        self.timestampUsec = timestampUsec
        self.author = author
        self.origin = origin
        self.canonical = canonical
        self.alternate = alternate
        self.summary = summary
        self.content = content
        self.categories = categories
    }

    public var isRead: Bool {
        categories.contains(FreshRSSLabel.read)
    }

    public var isStarred: Bool {
        categories.contains(FreshRSSLabel.starred)
    }

    public var preferredURL: URL? {
        canonical.first?.href ?? alternate.first?.href
    }

    public var preferredHTML: String? {
        content?.html ?? summary?.html
    }

    public var publishedAt: Date? {
        if let timestampUsec, let microseconds = Double(timestampUsec) {
            return Date(timeIntervalSince1970: microseconds / 1_000_000)
        }
        if let crawlTimeMsec, let milliseconds = Double(crawlTimeMsec) {
            return Date(timeIntervalSince1970: milliseconds / 1_000)
        }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case id, crawlTimeMsec, timestampUsec, title, author, origin
        case canonical, alternate, summary, content, categories
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        crawlTimeMsec = try container.decodeIfPresent(String.self, forKey: .crawlTimeMsec)
        timestampUsec = try container.decodeIfPresent(String.self, forKey: .timestampUsec)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled article"
        if let decoded = try? container.decodeIfPresent(FreshRSSAuthor.self, forKey: .author) {
            author = decoded
        } else if let name = try? container.decodeIfPresent(String.self, forKey: .author) {
            author = FreshRSSAuthor(name: name)
        } else {
            author = nil
        }
        origin = try container.decodeIfPresent(FreshRSSOrigin.self, forKey: .origin)
        canonical = try container.decodeIfPresent([FreshRSSLink].self, forKey: .canonical) ?? []
        alternate = try container.decodeIfPresent([FreshRSSLink].self, forKey: .alternate) ?? []
        summary = try container.decodeIfPresent(FreshRSSContent.self, forKey: .summary)
        content = try container.decodeIfPresent(FreshRSSContent.self, forKey: .content)
        categories = try container.decodeIfPresent([String].self, forKey: .categories) ?? []
    }
}

nonisolated public struct FreshRSSAuthor: Codable, Sendable, Equatable {
    public let name: String?
    public let email: String?
    public let href: URL?

    public init(name: String? = nil, email: String? = nil, href: URL? = nil) {
        self.name = name
        self.email = email
        self.href = href
    }
}

nonisolated public struct FreshRSSOrigin: Codable, Sendable, Equatable {
    public let streamID: String?
    public let title: String?
    public let htmlURL: URL?
    public let iconURL: URL?

    public init(streamID: String? = nil, title: String? = nil,
                htmlURL: URL? = nil, iconURL: URL? = nil) {
        self.streamID = streamID
        self.title = title
        self.htmlURL = htmlURL
        self.iconURL = iconURL
    }

    enum CodingKeys: String, CodingKey {
        case streamID = "streamId"
        case title
        case htmlURL = "htmlUrl"
        case iconURL = "iconUrl"
    }
}

nonisolated public struct FreshRSSLink: Codable, Sendable, Equatable {
    public let href: URL?
    public let type: String?

    public init(href: URL?, type: String? = nil) {
        self.href = href
        self.type = type
    }
}

nonisolated public struct FreshRSSContent: Codable, Sendable, Equatable {
    public let html: String?
    public let direction: String?

    public init(html: String?, direction: String? = nil) {
        self.html = html
        self.direction = direction
    }

    enum CodingKeys: String, CodingKey {
        case html = "content"
        case direction
    }
}

nonisolated public enum FreshRSSLabel {
    nonisolated public static let read = "user/-/state/com.google/read"
    nonisolated public static let starred = "user/-/state/com.google/starred"
    nonisolated public static let readingList = "user/-/state/com.google/reading-list"
}

nonisolated public extension FreshRSSSubscription {
    var resolvedFeedURL: URL? {
        if let feedURL, feedURL.scheme != nil { return feedURL }
        let raw = id.hasPrefix("feed/") ? String(id.dropFirst(5)) : id
        guard let url = URL(string: raw), url.scheme != nil else { return nil }
        return url
    }
}

nonisolated public extension FreshRSSItem {
    /// A transport-neutral snapshot that can be applied to the shared
    /// SwiftData `Article` model by the sync repository.
    var snapshot: FreshRSSArticleSnapshot {
        FreshRSSArticleSnapshot(
            remoteID: id,
            guid: id,
            title: title,
            url: preferredURL,
            author: author?.name,
            publishedAt: publishedAt,
            summary: summary?.html,
            contentHTML: content?.html,
            isRead: isRead,
            isStarred: isStarred,
            feedRemoteID: origin?.streamID
        )
    }
}

nonisolated public struct FreshRSSArticleSnapshot: Sendable, Equatable {
    public let remoteID: String
    public let guid: String
    public let title: String
    public let url: URL?
    public let author: String?
    public let publishedAt: Date?
    public let summary: String?
    public let contentHTML: String?
    public let isRead: Bool
    public let isStarred: Bool
    public let feedRemoteID: String?
}
