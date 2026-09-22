import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class SourcesViewModel {
    private var context: ModelContext?
    private(set) var feeds: [Feed] = []
    var isPresentingAddSource = false
    var isPresentingNewFolder = false
    var newFolderName = ""
    var statusMessage: String?
    private(set) var isImportingPack = false

    func configure(with context: ModelContext) { self.context = context; reload() }
    func reload() {
        guard let context else { return }
        feeds = (try? context.fetch(FetchDescriptor<Feed>(sortBy: [SortDescriptor(\.title)]))) ?? []
    }

    var folders: [FeedFolderGroup] {
        let occupied = FeedFolderGrouping.groups(from: feeds)
        var named: [String: [Feed]] = [:]
        var unfiled: [Feed] = []
        for group in occupied {
            switch group.folderID {
            case .named(let name): named[name] = group.feeds
            case .unfiled: unfiled = group.feeds
            }
        }
        for name in FolderStore.knownNames() where named[name] == nil {
            // Preserve canonical casing from FolderStore when no feeds yet.
            if named.keys.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { continue }
            named[name] = []
        }
        let namedGroups = named.keys
            .sorted(by: FeedFolderGrouping.compareFolderNames)
            .map { FeedFolderGroup(folderID: .named($0), feeds: named[$0] ?? []) }
        if unfiled.isEmpty { return namedGroups }
        return namedGroups + [FeedFolderGroup(folderID: .unfiled, feeds: unfiled)]
    }

    var folderNames: [String] { FolderStore.allNames(from: feeds) }

    func feeds(in folderID: FeedFolderID) -> [Feed] {
        folders.first(where: { $0.folderID == folderID })?.feeds ?? []
    }

    func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        FolderStore.remember(name)
        newFolderName = ""
        isPresentingNewFolder = false
        LibraryChange.noteStructureChanged()
        reload()
    }

    func move(_ feed: Feed, to folderName: String?) {
        guard let context else { return }
        let trimmed = folderName?.trimmingCharacters(in: .whitespacesAndNewlines)
        feed.folderName = (trimmed?.isEmpty == false) ? trimmed : nil
        if let trimmed, !trimmed.isEmpty { FolderStore.remember(trimmed) }
        LibraryChange.note(feed)
        try? context.save()
        reload()
    }

    func importAllSeededSources() {
        guard let context, !isImportingPack else { return }
        isImportingPack = true
        do {
            let result = try FeedSeedService().apply(in: context)
            UserDefaults.standard.set(true, forKey: AppPreferenceKey.didSeedTinyRSSCatalog)
            UserDefaults.standard.set(FeedSeedCatalog.version, forKey: AppPreferenceKey.seedCatalogVersion)
            reload()
            LibraryChange.noteStructureChanged()
            if result.inserted == 0 && result.updated == 0 && result.removed == 0 {
                statusMessage = "All seeded sources are already loaded."
                isImportingPack = false
                return
            }
            statusMessage = "Restored \(result.inserted) source\(result.inserted == 1 ? "" : "s"). Updating…"
            Task {
                defer { isImportingPack = false }
                let freshRSS = SyncProvider.freshRSS.rawValue
                if let account = try? context.fetch(FetchDescriptor<SyncAccount>(predicate: #Predicate { $0.providerRawValue == freshRSS })).first,
                   account.isEnabled {
                    try? await FreshRSSSyncService().subscribeLocalFeeds(in: context)
                }
                do {
                    try await FeedService().refreshAll(in: context)
                    statusMessage = "Library ready · \(result.inserted) new, \(result.updated) updated."
                    reload()
                } catch {
                    statusMessage = RefreshFailure.message(for: error) ?? error.localizedDescription
                }
            }
        } catch {
            statusMessage = error.localizedDescription
            isImportingPack = false
        }
    }

    func importCuratedPack() {
        importAllSeededSources()
    }
}

@MainActor
@Observable
final class AddSourceViewModel {
    private let feedService: any FeedRepository
    private let freshRSSService: any FreshRSSSyncing

    /// One URL / website per line. Paste a list to add several at once.
    var addressList = ""
    /// Empty string means Unfiled.
    var selectedFolder = ""
    var newFolderName = ""
    var isCreatingNewFolder = false
    private(set) var isAdding = false
    private(set) var progressLabel: String?
    var presentedError: String?
    private(set) var addedCount = 0
    var availableFolders: [String] = []

    init() {
        feedService = FeedService()
        freshRSSService = FreshRSSSyncService()
    }

    init(feedService: any FeedRepository, freshRSSService: any FreshRSSSyncing) {
        self.feedService = feedService
        self.freshRSSService = freshRSSService
    }

    func configureFolders(from feeds: [Feed], preferred: String? = nil) {
        availableFolders = FolderStore.allNames(from: feeds)
        if let preferred, availableFolders.contains(where: { $0.caseInsensitiveCompare(preferred) == .orderedSame }) {
            selectedFolder = preferred
        }
    }

    var resolvedFolderName: String? {
        if isCreatingNewFolder {
            let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        }
        let selected = selectedFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        return selected.isEmpty ? nil : selected
    }

    var addresses: [String] {
        addressList
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func add(in context: ModelContext) async -> Bool {
        guard !isAdding else { return false }
        let inputs = addresses
        guard !inputs.isEmpty else {
            presentedError = "Paste at least one website, article, or file URL."
            return false
        }

        isAdding = true
        presentedError = nil
        addedCount = 0
        let folder = resolvedFolderName
        if let folder { FolderStore.remember(folder) }

        let freshRSS = SyncProvider.freshRSS.rawValue
        let account = try? context.fetch(FetchDescriptor<SyncAccount>(predicate: #Predicate { $0.providerRawValue == freshRSS })).first
        let useFreshRSS = account?.isEnabled == true

        var failures: [String] = []
        for (index, input) in inputs.enumerated() {
            progressLabel = inputs.count == 1 ? "Adding…" : "Adding \(index + 1) of \(inputs.count)…"
            do {
                if useFreshRSS, !FeedService.importsWithoutRSS(input) {
                    _ = try await freshRSSService.addSubscription(from: input, folderName: folder, in: context)
                } else {
                    _ = try await feedService.addSource(from: input, folderName: folder, in: context)
                }
                addedCount += 1
            } catch {
                failures.append("\(input): \(error.localizedDescription)")
            }
        }

        progressLabel = nil
        isAdding = false

        if addedCount == 0 {
            presentedError = failures.first ?? "Could not add those sources."
            return false
        }
        if !failures.isEmpty {
            presentedError = "Added \(addedCount), \(failures.count) failed.\n\(failures.prefix(3).joined(separator: "\n"))"
        }
        addressList = ""
        LibraryChange.noteStructureChanged()
        return true
    }
}

@MainActor
@Observable
final class SourceDetailViewModel {
    let feed: Feed
    private let context: ModelContext
    private let freshRSSService: any FreshRSSSyncing
    var isConfirmingRemoval = false
    var presentedError: String?
    var availableFolders: [String] = []

    init(feed: Feed, context: ModelContext) {
        self.feed = feed
        self.context = context
        self.freshRSSService = FreshRSSSyncService()
        reloadFolders()
    }

    func reloadFolders() {
        let feeds = (try? context.fetch(FetchDescriptor<Feed>())) ?? []
        availableFolders = FolderStore.allNames(from: feeds)
    }

    var folderSelection: String {
        get { feed.folderName ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            feed.folderName = trimmed.isEmpty ? nil : trimmed
            if !trimmed.isEmpty { FolderStore.remember(trimmed) }
            LibraryChange.note(feed)
            try? context.save()
        }
    }

    var isEnabled: Bool {
        get { feed.isEnabled }
        set { feed.isEnabled = newValue; LibraryChange.note(feed); try? context.save() }
    }
    var includeInToday: Bool {
        get { feed.includeInToday }
        set { feed.includeInToday = newValue; LibraryChange.note(feed); try? context.save() }
    }
    var includeVideos: Bool {
        get { feed.includeVideos }
        set { feed.includeVideos = newValue; LibraryChange.note(feed); try? context.save() }
    }
    var includeShorts: Bool {
        get { feed.includeShorts }
        set { feed.includeShorts = newValue; LibraryChange.note(feed); try? context.save() }
    }
    var blockedWords: String {
        get { feed.blockedWords }
        set { feed.blockedWords = newValue; LibraryChange.note(feed); try? context.save() }
    }
    func remove() async {
        do {
            try await freshRSSService.removeSubscription(feed, in: context)
        } catch {
            presentedError = error.localizedDescription
            LibraryChange.noteRemovedFeed(feed)
            context.delete(feed)
            try? context.save()
        }
    }

    var recentArticles: [Article] {
        feed.articles
            .sorted { $0.publishedAt > $1.publishedAt }
            .prefix(20)
            .map { $0 }
    }
}
