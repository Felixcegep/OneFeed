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
    /// Primary folder, kept for FreshRSS and older library files. Nil means unfiled.
    /// Readers should use `memberships`, which also includes every other folder.
    var folderName: String?
    /// Every folder this source appears in. Empty falls back to `folderName`.
    var folderNames: [String] = []
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
        folderNames: [String] = [],
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
        let resolved = FeedMembership.normalize(
            folderNames.isEmpty
                ? (FeedMembership.normalized(folderName).map { [$0] } ?? [])
                : folderNames
        )
        self.folderNames = resolved
        self.folderName = resolved.first
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

    /// Folders this source appears in. A legacy row with only `folderName` still resolves.
    var memberships: [String] {
        let stored = FeedMembership.normalize(folderNames)
        if !stored.isEmpty { return stored }
        if let legacy = FeedMembership.normalized(folderName) { return [legacy] }
        return []
    }

    func containsFolder(_ name: String) -> Bool {
        guard let name = FeedMembership.normalized(name) else { return false }
        return memberships.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Graphite line shown inside one folder when the source also lives elsewhere.
    func alsoInLine(excluding folder: String) -> String? {
        let others = memberships.filter { $0.caseInsensitiveCompare(folder) != .orderedSame }
        guard !others.isEmpty else { return nil }
        return "Also in \(others.joined(separator: ", "))"
    }

    /// Where an existing source already lives, shown while adding it to another folder.
    var filedInLine: String {
        let names = memberships
        if names.isEmpty { return "Unfiled" }
        return "In \(names.joined(separator: ", "))"
    }

    func setMemberships(_ names: [String], touch: Bool = true) {
        let normalized = FeedMembership.normalize(names)
        folderNames = normalized
        folderName = normalized.first
        if touch { touchLibrary() }
        for name in normalized { FolderStore.remember(name) }
    }

    /// Adds a folder and leaves the others in place. Returns false when it was already there.
    @discardableResult
    func addFolder(_ name: String, touch: Bool = true) -> Bool {
        guard let name = FeedMembership.normalized(name) else { return false }
        var names = memberships
        guard !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return false }
        names.append(name)
        setMemberships(names, touch: touch)
        return true
    }

    /// Drops one folder. The source stays, and becomes Unfiled when this was the last label.
    @discardableResult
    func removeFolder(_ name: String, touch: Bool = true) -> Bool {
        let names = memberships
        let next = names.filter { $0.caseInsensitiveCompare(name) != .orderedSame }
        guard next.count != names.count else { return false }
        setMemberships(next, touch: touch)
        return true
    }

    /// This folder only. Nil clears every label and leaves the source Unfiled.
    func replaceFolders(with name: String?, touch: Bool = true) {
        if let name = FeedMembership.normalized(name) {
            setMemberships([name], touch: touch)
        } else {
            setMemberships([], touch: touch)
        }
    }

    func renameMembership(from: String, to: String, touch: Bool = true) {
        guard let to = FeedMembership.normalized(to) else { return }
        var names = memberships
        guard let index = names.firstIndex(where: { $0.caseInsensitiveCompare(from) == .orderedSame }) else { return }
        if names.contains(where: { $0.caseInsensitiveCompare(to) == .orderedSame }) {
            names.remove(at: index)
        } else {
            names[index] = to
        }
        setMemberships(names, touch: touch)
    }

    /// FreshRSS has one category. That category becomes the primary folder; local-only labels stay.
    func applyRemotePrimaryFolder(_ name: String?) {
        let remote = FeedMembership.normalized(name)
        let current = memberships
        var next: [String] = []
        if let remote { next.append(remote) }
        for extra in current.dropFirst() {
            if let remote, extra.caseInsensitiveCompare(remote) == .orderedSame { continue }
            if next.contains(where: { $0.caseInsensitiveCompare(extra) == .orderedSame }) { continue }
            next.append(extra)
        }
        guard next != current || folderNames != next else { return }
        folderNames = next
        folderName = next.first
        if let remote { FolderStore.remember(remote) }
    }

    /// RSS and Atom subscriptions refresh in place. A PDF, EPUB, or single page is imported once.
    var refreshesOverRSS: Bool {
        switch contentKind {
        case "pdf", "epub", "page": false
        default: true
        }
    }
}

nonisolated enum FeedMembership {
    static func normalized(_ name: String?) -> String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalize(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for name in names {
            guard let trimmed = normalized(name) else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            ordered.append(trimmed)
        }
        return ordered
    }
}
