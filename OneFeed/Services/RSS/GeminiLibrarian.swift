import Foundation
import SwiftData

enum GeminiFeedMatch: Equatable {
    case one(UUID)
    case none
    case many([String])
}

struct GeminiToolResult: Equatable, Sendable {
    var ok: Bool
    var message: String
    var needsConfirmation = false
    var pendingRemoval: GeminiPendingRemoval?

    var responseObject: [String: Any] {
        ["ok": ok, "message": message]
    }
}

struct GeminiPendingRemoval: Equatable, Sendable, Identifiable {
    var id: UUID { feedID }
    var feedID: UUID
    var title: String
    var call: GeminiFunctionCall
}

enum GeminiLibraryTools {
    static let names = [
        "list_library",
        "list_not_interested",
        "search_sources",
        "add_source",
        "remove_source",
        "move_source",
        "add_to_folder",
        "remove_from_folder",
        "archive_source",
        "create_folder",
        "rename_folder",
        "set_folder_emoji",
        "update_source"
    ]

    static var declarations: [[String: Any]] {
        [
            declaration("list_library", "List folders and sources currently in the library.", [:], []),
            declaration(
                "list_not_interested",
                "List articles the reader marked not interested, grouped by source, with folder and Today flags.",
                [:],
                []
            ),
            declaration(
                "search_sources",
                "Find sources by title, site, or URL. When the query is a folder name, list the sources in that folder. Returns title, site, and folders. Read-only.",
                ["query": string("Source title, site, URL, or folder name.")],
                ["query"]
            ),
            declaration(
                "add_source",
                "Subscribe to a website or RSS/Atom URL. Use the homepage if the reader names a publication. If that URL is already subscribed, add the folder and do not create a second source.",
                [
                    "url": string("Website or feed URL."),
                    "folder": string("Existing or new folder name. Omit to leave unfiled.")
                ],
                ["url"]
            ),
            declaration(
                "remove_source",
                "Remove a subscribed source and its locally stored articles. Only when the reader is explicit.",
                ["source": string("Exact source title or URL from the library.")],
                ["source"]
            ),
            declaration(
                "archive_source",
                "Move a source to Archive and take it out of Today. The subscription stays. Use this when the reader wants to keep a source but stop seeing it daily.",
                ["source": string("Exact source title or URL from the library.")],
                ["source"]
            ),
            declaration(
                "move_source",
                "File a source in this folder only and drop every other folder. Use an empty folder string for Unfiled. If the reader wants to keep other folders, use add_to_folder instead.",
                [
                    "source": string("Exact source title or URL from the library."),
                    "folder": string("The only folder to keep, or empty for Unfiled.")
                ],
                ["source"]
            ),
            declaration(
                "add_to_folder",
                "Add a source to a folder and keep its other folders. Creates the folder if it is new. If the source is already in that folder, leave it there.",
                [
                    "source": string("Exact source title or URL from the library."),
                    "folder": string("Folder to add. Other folders stay.")
                ],
                ["source", "folder"]
            ),
            declaration(
                "remove_from_folder",
                "Drop one folder label from a source. The subscription stays. If this was the last folder, the source becomes Unfiled.",
                [
                    "source": string("Exact source title or URL from the library."),
                    "folder": string("Folder label to drop.")
                ],
                ["source", "folder"]
            ),
            declaration(
                "create_folder",
                "Create a folder. Sources can be added to it afterwards.",
                [
                    "name": string("Folder name."),
                    "emoji": string("Optional emoji for the folder icon.")
                ],
                ["name"]
            ),
            declaration(
                "rename_folder",
                "Rename a folder and keep its sources.",
                [
                    "from": string("Current folder name."),
                    "to": string("New folder name.")
                ],
                ["from", "to"]
            ),
            declaration(
                "set_folder_emoji",
                "Change the emoji icon for a folder.",
                [
                    "folder": string("Folder name."),
                    "emoji": string("Emoji glyph.")
                ],
                ["folder", "emoji"]
            ),
            declaration(
                "update_source",
                "Change whether a source is enabled, included in Today, includes videos, or uses blocked words.",
                [
                    "source": string("Exact source title or URL from the library."),
                    "enabled": boolean("false pauses the source."),
                    "include_in_today": boolean("false keeps it out of Today."),
                    "include_videos": boolean("Whether video items are kept."),
                    "include_shorts": boolean("Whether videos shorter than 3 minutes are kept."),
                    "blocked_words": string("Comma-separated words that never enter Today or Feed.")
                ],
                ["source"]
            )
        ]
    }

    static func snapshot(feeds: [Feed], folderNames: [String], limit: Int = 80) -> String {
        var named: [String: [Feed]] = [:]
        var unfiled: [Feed] = []
        for feed in feeds {
            let folders = feed.memberships
            if folders.isEmpty {
                unfiled.append(feed)
            } else {
                for folder in folders {
                    named[folder, default: []].append(feed)
                }
            }
        }
        for name in folderNames where named[name] == nil {
            if named.keys.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { continue }
            named[name] = []
        }

        var lines: [String] = []
        var remaining = limit
        let orderedNames = named.keys.sorted(by: FeedFolderGrouping.compareFolderNames)
        for name in orderedNames {
            let group = (named[name] ?? []).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            lines.append("\(FolderEmoji.glyph(for: name)) \(name)")
            appendFeeds(group, into: &lines, remaining: &remaining, inFolder: name)
        }
        if !unfiled.isEmpty {
            lines.append("\(FolderEmoji.glyph(for: "Unfiled")) Unfiled")
            appendFeeds(
                unfiled.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending },
                into: &lines,
                remaining: &remaining,
                inFolder: nil
            )
        }
        if remaining < 0 {
            lines.append("…and \(abs(remaining)) more. Call list_library for the rest.")
        }
        if lines.isEmpty { return "The library is empty." }
        return lines.joined(separator: "\n")
    }

    static func matchFeeds(query: String, in feeds: [Feed]) -> GeminiFeedMatch {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return .none }

        let exactTitle = feeds.filter { $0.title.caseInsensitiveCompare(needle) == .orderedSame }
        if exactTitle.count == 1, let feed = exactTitle.first { return .one(feed.id) }
        if exactTitle.count > 1 { return .many(exactTitle.map(\.title)) }

        if let url = FeedService.normalizedURL(from: needle) {
            let exactURL = feeds.filter {
                $0.feedURL.absoluteString.caseInsensitiveCompare(url.absoluteString) == .orderedSame
                    || $0.websiteURL?.absoluteString.caseInsensitiveCompare(url.absoluteString) == .orderedSame
            }
            if exactURL.count == 1, let feed = exactURL.first { return .one(feed.id) }

            let host = url.host()?.lowercased() ?? ""
            if !host.isEmpty {
                let hostMatches = feeds.filter { feed in
                    feed.feedURL.host()?.lowercased() == host || feed.websiteURL?.host()?.lowercased() == host
                }
                if hostMatches.count == 1, let feed = hostMatches.first { return .one(feed.id) }
                if hostMatches.count > 1 { return .many(hostMatches.map(\.title)) }
            }
        }

        let contains = feeds.filter { $0.title.localizedCaseInsensitiveContains(needle) }
        if contains.count == 1, let feed = contains.first { return .one(feed.id) }
        if contains.count > 1 { return .many(contains.map(\.title)) }
        return .none
    }

    /// Title, site, and folders for matching sources. A query that names a folder also lists that folder. Read-only.
    static func search(query: String, feeds: [Feed], folderNames: [String]) -> String {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return "A search query is required." }

        let matched = Self.feeds(matching: matchFeeds(query: needle, in: feeds), in: feeds)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        var lines = matched.map(describe)

        if let folder = matchFolder(name: needle, in: folderNames) {
            if !lines.isEmpty { lines.append("") }
            lines.append("\(FolderEmoji.glyph(for: folder)) \(folder)")
            let members = feeds
                .filter { $0.containsFolder(folder) }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            if members.isEmpty {
                lines.append("- (empty)")
            } else {
                lines.append(contentsOf: members.map(describe))
            }
        }

        if lines.isEmpty { return "No source matches “\(needle)”." }
        return lines.joined(separator: "\n")
    }

    static func matchFolder(name: String, in folderNames: [String]) -> String? {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        return folderNames.first { $0.caseInsensitiveCompare(needle) == .orderedSame }
    }

    private static func appendFeeds(
        _ feeds: [Feed],
        into lines: inout [String],
        remaining: inout Int,
        inFolder folder: String?
    ) {
        if feeds.isEmpty {
            lines.append("- (empty)")
            return
        }
        for feed in feeds {
            remaining -= 1
            if remaining < 0 { return }
            let host = feed.websiteURL?.host() ?? feed.feedURL.host() ?? feed.feedURL.absoluteString
            var flags: [String] = []
            if !feed.isEnabled { flags.append("paused") }
            if !feed.includeInToday { flags.append("not in Today") }
            var suffix = flags.isEmpty ? "" : " · " + flags.joined(separator: ", ")
            if let folder, let also = feed.alsoInLine(excluding: folder) {
                let names = also.hasPrefix("Also in ") ? String(also.dropFirst("Also in ".count)) : also
                suffix += " · also in \(names)"
            }
            lines.append("- \(feed.title) (\(host))\(suffix)")
        }
    }

    private static func describe(_ feed: Feed) -> String {
        let host = feed.websiteURL?.host() ?? feed.feedURL.host() ?? feed.feedURL.absoluteString
        return "- \(feed.title) (\(host)) · \(feed.filedInLine)"
    }

    private static func feeds(matching match: GeminiFeedMatch, in feeds: [Feed]) -> [Feed] {
        switch match {
        case .one(let id):
            return feeds.filter { $0.id == id }
        case .none:
            return []
        case .many(let titles):
            return feeds.filter { feed in
                titles.contains { $0.caseInsensitiveCompare(feed.title) == .orderedSame }
            }
        }
    }

    private static func declaration(
        _ name: String,
        _ description: String,
        _ properties: [String: [String: String]],
        _ required: [String]
    ) -> [String: Any] {
        var parameters: [String: Any] = [
            "type": "OBJECT",
            "properties": properties
        ]
        if !required.isEmpty { parameters["required"] = required }
        return [
            "name": name,
            "description": description,
            "parameters": parameters
        ]
    }

    private static func string(_ description: String) -> [String: String] {
        ["type": "STRING", "description": description]
    }

    private static func boolean(_ description: String) -> [String: String] {
        ["type": "BOOLEAN", "description": description]
    }
}

@MainActor
final class GeminiLibrarian {
    private let feedService: any FeedRepository
    private let freshRSSService: any FreshRSSSyncing

    init(
        feedService: (any FeedRepository)? = nil,
        freshRSSService: (any FreshRSSSyncing)? = nil
    ) {
        self.feedService = feedService ?? FeedService()
        self.freshRSSService = freshRSSService ?? FreshRSSSyncService()
    }

    func systemInstruction(in context: ModelContext) -> String {
        """
        You are a librarian inside OneFeed, an RSS reader. Change subscriptions and folders only through the provided tools.

        Current library:
        \(snapshot(in: context))

        \(NotInterestedLog.snapshot(in: context))

        Rules:
        - Prefer existing folder names. Create a folder only when asked or when a new group is clearly needed.
        - The same title in two folders is one source.
        - add_source accepts a website or RSS URL. Use the site’s homepage if the reader names a publication. If that URL is already subscribed, add the folder and do not create a second source.
        - Identify sources by their exact title or URL from the library. If several match, ask.
        - search_sources before guessing when the library list is long.
        - add_to_folder keeps other folders. move_source means this folder only.
        - remove_from_folder drops one label. remove_source deletes the subscription and its locally stored articles. Only do that when the reader is explicit.
        - archive_source moves a source to Archive and sets include_in_today=false. The subscription stays.
        - Use the not-interested log to notice noisy sources. Suggest Archive, blocked words, or removal. Only remove when the reader is explicit.
        - include_in_today controls whether a source enters Today. Pausing a source uses enabled=false.
        - After you change something, say what changed in one or two short sentences. Do not mention tools or being an AI.
        - You cannot change reading fonts, FreshRSS, iCloud, Google Drive, or the API key.
        """
    }

    func snapshot(in context: ModelContext) -> String {
        let feeds = fetchFeeds(in: context)
        return GeminiLibraryTools.snapshot(feeds: feeds, folderNames: FolderStore.allNames(from: feeds))
    }

    func perform(_ call: GeminiFunctionCall, in context: ModelContext, allowRemoval: Bool) async -> GeminiToolResult {
        switch call.name {
        case "list_library":
            return .init(ok: true, message: snapshot(in: context))
        case "list_not_interested":
            return .init(ok: true, message: NotInterestedLog.snapshot(in: context, sources: 20, articlesPerSource: 6))
        case "search_sources":
            return searchSources(call, in: context)
        case "add_source":
            return await addSource(call, in: context)
        case "remove_source":
            return await removeSource(call, in: context, allowRemoval: allowRemoval)
        case "move_source":
            return moveSource(call, in: context)
        case "add_to_folder":
            return addToFolder(call, in: context)
        case "remove_from_folder":
            return removeFromFolder(call, in: context)
        case "archive_source":
            return archiveSource(call, in: context)
        case "create_folder":
            return createFolder(call)
        case "rename_folder":
            return renameFolder(call, in: context)
        case "set_folder_emoji":
            return setFolderEmoji(call, in: context)
        case "update_source":
            return updateSource(call, in: context)
        default:
            return .init(ok: false, message: "Unknown action \(call.name).")
        }
    }

    private func addSource(_ call: GeminiFunctionCall, in context: ModelContext) async -> GeminiToolResult {
        guard let url = call.string("url") else {
            return .init(ok: false, message: "A website, article, or file URL is required.")
        }
        let folder = call.string("folder")
        do {
            let feed: Feed
            if usesFreshRSS(in: context), !FeedService.importsWithoutRSS(url) {
                feed = try await freshRSSService.addSubscription(from: url, folderName: folder, in: context)
            } else {
                feed = try await feedService.addSource(from: url, folderName: folder, in: context)
            }
            LibraryChange.noteStructureChanged()
            if let folder, !folder.isEmpty {
                return .init(ok: true, message: "Added \(feed.title) to \(folder).")
            }
            return .init(ok: true, message: "Added \(feed.title).")
        } catch {
            return .init(ok: false, message: UserFacingFailure.message(for: error, fallback: "Couldn’t add that source."))
        }
    }

    private func removeSource(_ call: GeminiFunctionCall, in context: ModelContext, allowRemoval: Bool) async -> GeminiToolResult {
        let resolved = resolveFeed(call.string("source"), in: context)
        guard let feed = resolved.feed else {
            return .init(ok: false, message: resolved.message ?? "Could not find that source.")
        }
        if !allowRemoval {
            return GeminiToolResult(
                ok: true,
                message: "Waiting to remove \(feed.title).",
                needsConfirmation: true,
                pendingRemoval: GeminiPendingRemoval(feedID: feed.id, title: feed.title, call: call)
            )
        }
        let title = feed.title
        do {
            try await freshRSSService.removeSubscription(feed, in: context)
            return .init(ok: true, message: "Removed \(title).")
        } catch {
            context.delete(feed)
            do {
                try context.save()
                LibraryChange.noteRemovedFeed(feed)
                return .init(ok: true, message: "Removed \(title).")
            } catch {
                context.rollback()
                return .init(ok: false, message: UserFacingFailure.message(for: error, fallback: "Couldn’t remove that source."))
            }
        }
    }

    private func archiveSource(_ call: GeminiFunctionCall, in context: ModelContext) -> GeminiToolResult {
        let resolved = resolveFeed(call.string("source"), in: context)
        guard let feed = resolved.feed else {
            return .init(ok: false, message: resolved.message ?? "Could not find that source.")
        }
        let archiveName = NotInterestedLog.archiveFolderName
        let alreadyArchived = feed.memberships.count == 1
            && feed.memberships.contains { $0.caseInsensitiveCompare(archiveName) == .orderedSame }
            && feed.includeInToday == false
        if alreadyArchived {
            return .init(ok: true, message: "\(feed.title) is already in Archive and out of Today.")
        }
        do {
            try NotInterestedLog.archive(feed, in: context)
        } catch {
            return .init(ok: false, message: UserFacingFailure.message(for: error, fallback: "Couldn’t update that source."))
        }
        return .init(ok: true, message: "Moved \(feed.title) to Archive and took it out of Today.")
    }

    private func moveSource(_ call: GeminiFunctionCall, in context: ModelContext) -> GeminiToolResult {
        let resolved = resolveFeed(call.string("source"), in: context)
        guard let feed = resolved.feed else {
            return .init(ok: false, message: resolved.message ?? "Could not find that source.")
        }
        let folder = call.string("folder").map { canonicalFolder($0, on: feed, in: context) }
        feed.replaceFolders(with: folder)
        LibraryChange.note(feed)
        if let failure = commit(context) {
            return .init(ok: false, message: failure)
        }
        if let folder {
            return .init(ok: true, message: "Moved \(feed.title) to \(folder).")
        }
        return .init(ok: true, message: "Moved \(feed.title) to Unfiled.")
    }

    private func addToFolder(_ call: GeminiFunctionCall, in context: ModelContext) -> GeminiToolResult {
        let resolved = resolveFeed(call.string("source"), in: context)
        guard let feed = resolved.feed else {
            return .init(ok: false, message: resolved.message ?? "Could not find that source.")
        }
        guard let requested = call.string("folder") else {
            return .init(ok: false, message: "A folder name is required.")
        }
        let folder = canonicalFolder(requested, on: feed, in: context)
        if feed.addFolder(folder) {
            LibraryChange.note(feed)
            if let failure = commit(context) {
                return .init(ok: false, message: failure)
            }
            return .init(ok: true, message: "Added \(feed.title) to \(folder).")
        }
        if feed.containsFolder(folder) {
            return .init(ok: true, message: "\(feed.title) is already in \(folder).")
        }
        return .init(ok: false, message: "A folder name is required.")
    }

    private func removeFromFolder(_ call: GeminiFunctionCall, in context: ModelContext) -> GeminiToolResult {
        let resolved = resolveFeed(call.string("source"), in: context)
        guard let feed = resolved.feed else {
            return .init(ok: false, message: resolved.message ?? "Could not find that source.")
        }
        guard let requested = call.string("folder") else {
            return .init(ok: false, message: "A folder name is required.")
        }
        let folder = canonicalFolder(requested, on: feed, in: context)
        guard feed.removeFolder(folder) else {
            return .init(ok: true, message: "\(feed.title) is not in \(folder).")
        }
        LibraryChange.note(feed)
        if let failure = commit(context) {
            return .init(ok: false, message: failure)
        }
        if feed.memberships.isEmpty {
            return .init(ok: true, message: "Removed \(feed.title) from \(folder). It is now Unfiled.")
        }
        return .init(ok: true, message: "Removed \(feed.title) from \(folder).")
    }

    private func searchSources(_ call: GeminiFunctionCall, in context: ModelContext) -> GeminiToolResult {
        guard let query = call.string("query") else {
            return .init(ok: false, message: "A search query is required.")
        }
        let feeds = fetchFeeds(in: context)
        let message = GeminiLibraryTools.search(
            query: query,
            feeds: feeds,
            folderNames: FolderStore.allNames(from: feeds)
        )
        return .init(ok: true, message: message)
    }

    private func createFolder(_ call: GeminiFunctionCall) -> GeminiToolResult {
        guard let name = call.string("name") else {
            return .init(ok: false, message: "A folder name is required.")
        }
        FolderStore.remember(name)
        if let emoji = call.string("emoji") {
            FolderEmoji.set(emoji, for: name)
        }
        LibraryChange.noteStructureChanged()
        return .init(ok: true, message: "Created folder \(name).")
    }

    private func renameFolder(_ call: GeminiFunctionCall, in context: ModelContext) -> GeminiToolResult {
        guard let fromQuery = call.string("from"), let to = call.string("to") else {
            return .init(ok: false, message: "Both folder names are required.")
        }
        let feeds = fetchFeeds(in: context)
        guard let from = GeminiLibraryTools.matchFolder(name: fromQuery, in: FolderStore.allNames(from: feeds)) else {
            return .init(ok: false, message: "No folder named \(fromQuery).")
        }
        if from.caseInsensitiveCompare(to) == .orderedSame {
            return .init(ok: true, message: "Folder \(from) already has that name.")
        }
        let emoji = FolderEmoji.glyph(for: from)
        for feed in feeds where feed.containsFolder(from) {
            feed.renameMembership(from: from, to: to)
            LibraryChange.note(feed)
        }
        FolderStore.remember(to)
        FolderStore.remove(from)
        FolderEmoji.set(emoji, for: to)
        LibraryChange.noteStructureChanged()
        if let failure = commit(context) {
            FolderStore.remember(from)
            FolderStore.remove(to)
            FolderEmoji.set(emoji, for: from)
            return .init(ok: false, message: failure)
        }
        return .init(ok: true, message: "Renamed \(from) to \(to).")
    }

    private func setFolderEmoji(_ call: GeminiFunctionCall, in context: ModelContext) -> GeminiToolResult {
        guard let folderQuery = call.string("folder"), let emoji = call.string("emoji") else {
            return .init(ok: false, message: "A folder and an emoji are required.")
        }
        let feeds = fetchFeeds(in: context)
        guard let folder = GeminiLibraryTools.matchFolder(name: folderQuery, in: FolderStore.allNames(from: feeds)) else {
            return .init(ok: false, message: "No folder named \(folderQuery).")
        }
        FolderEmoji.set(emoji, for: folder)
        LibraryChange.noteStructureChanged()
        return .init(ok: true, message: "Set \(folder) to \(emoji).")
    }

    private func updateSource(_ call: GeminiFunctionCall, in context: ModelContext) -> GeminiToolResult {
        let resolved = resolveFeed(call.string("source"), in: context)
        guard let feed = resolved.feed else {
            return .init(ok: false, message: resolved.message ?? "Could not find that source.")
        }
        var changes: [String] = []
        if let enabled = call.bool("enabled") {
            feed.isEnabled = enabled
            changes.append(enabled ? "enabled" : "paused")
        }
        if let today = call.bool("include_in_today") {
            feed.includeInToday = today
            changes.append(today ? "in Today" : "out of Today")
        }
        if let videos = call.bool("include_videos") {
            feed.includeVideos = videos
            changes.append(videos ? "videos on" : "videos off")
        }
        if let shorts = call.bool("include_shorts") {
            feed.includeShorts = shorts
            changes.append(shorts ? "Shorts on" : "Shorts off")
        }
        if let blocked = call.arguments["blocked_words"] {
            feed.blockedWords = blocked
            changes.append("blocked words updated")
        }
        guard !changes.isEmpty else {
            return .init(ok: false, message: "No source settings to change.")
        }
        LibraryChange.note(feed)
        do {
            if call.bool("enabled") != nil || call.bool("include_in_today") != nil {
                try DailyDeckService.reconcileMembership(in: context)
            } else {
                try context.save()
            }
        } catch {
            context.rollback()
            return .init(ok: false, message: UserFacingFailure.message(for: error, fallback: "Couldn’t update that source."))
        }
        return .init(ok: true, message: "Updated \(feed.title): \(changes.joined(separator: ", ")).")
    }

    private func commit(_ context: ModelContext) -> String? {
        do {
            try context.save()
            return nil
        } catch {
            context.rollback()
            return UserFacingFailure.message(for: error, fallback: "Couldn’t update that source.")
        }
    }

    private func canonicalFolder(_ requested: String, on feed: Feed, in context: ModelContext) -> String {
        if let membership = feed.memberships.first(where: { $0.caseInsensitiveCompare(requested) == .orderedSame }) {
            return membership
        }
        let names = FolderStore.allNames(from: fetchFeeds(in: context))
        return GeminiLibraryTools.matchFolder(name: requested, in: names) ?? requested
    }

    private func resolveFeed(_ query: String?, in context: ModelContext) -> (feed: Feed?, message: String?) {
        guard let query else { return (nil, "Name the source by title or URL.") }
        let feeds = fetchFeeds(in: context)
        switch GeminiLibraryTools.matchFeeds(query: query, in: feeds) {
        case .one(let id):
            if let feed = feeds.first(where: { $0.id == id }) { return (feed, nil) }
            return (nil, "Could not find that source.")
        case .none:
            return (nil, "No source matches “\(query)”.")
        case .many(let titles):
            return (nil, "Several sources match: \(titles.joined(separator: ", ")). Name one exactly.")
        }
    }

    private func fetchFeeds(in context: ModelContext) -> [Feed] {
        (try? context.fetch(FetchDescriptor<Feed>(sortBy: [SortDescriptor(\.title)]))) ?? []
    }

    private func usesFreshRSS(in context: ModelContext) -> Bool {
        let freshRSS = SyncProvider.freshRSS.rawValue
        let account = try? context.fetch(FetchDescriptor<SyncAccount>(predicate: #Predicate { $0.providerRawValue == freshRSS })).first
        return account?.isEnabled == true
    }
}
