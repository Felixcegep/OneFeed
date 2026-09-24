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
    var statusTitle: String?
    var statusMessage: String?
    var saveError: String?
    private(set) var isImportingPack = false

    func configure(with context: ModelContext) { self.context = context; reload() }
    func reload() {
        guard let context else { return }
        feeds = (try? context.fetch(FetchDescriptor<Feed>(sortBy: [SortDescriptor(\.title)]))) ?? []
    }

    func presentStatus(_ title: String, message: String) {
        statusTitle = title
        statusMessage = message
    }

    func clearStatus() {
        statusTitle = nil
        statusMessage = nil
    }

    private var cachedFolderEdge = Int.min
    private var cachedFolders: [FeedFolderGroup] = []

    /// Folder groups stay put until a source or a remembered folder name changes.
    var folders: [FeedFolderGroup] { folders(matching: feeds) }

    /// Groups the feeds already loaded. The source list can draw before `reload()` fetches again.
    func folders(matching feeds: [Feed]) -> [FeedFolderGroup] {
        let edge = Self.folderEdge(of: feeds)
        if edge == cachedFolderEdge { return cachedFolders }
        cachedFolders = FeedFolderGrouping.groupsIncludingKnownEmpty(from: feeds)
        cachedFolderEdge = edge
        return cachedFolders
    }

    private static func folderEdge(of feeds: [Feed]) -> Int {
        var token = ListIdentity.token(ids: feeds.lazy.map(\.id))
        for feed in feeds {
            token = token &* 31 &+ feed.title.hashValue
            token = token &* 31 &+ feed.memberships.hashValue
            token = token &* 31 &+ (feed.isEnabled ? 1 : 0)
        }
        for name in FolderStore.knownNames() {
            token = token &* 31 &+ name.hashValue
        }
        return token
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

    func add(_ feed: Feed, to folderName: String) {
        guard let context, feed.addFolder(folderName) else { return }
        LibraryChange.note(feed)
        do {
            try context.save()
        } catch {
            feed.removeFolder(folderName)
            saveError = UserFacingFailure.message(for: error, fallback: "Couldn’t update that source.")
        }
        reload()
    }

    func remove(_ feed: Feed, from folderName: String) {
        guard let context, feed.removeFolder(folderName) else { return }
        LibraryChange.note(feed)
        do {
            try context.save()
        } catch {
            feed.addFolder(folderName)
            saveError = UserFacingFailure.message(for: error, fallback: "Couldn’t update that source.")
        }
        reload()
    }

    func toggle(_ feed: Feed, folder folderName: String) {
        if feed.containsFolder(folderName) {
            remove(feed, from: folderName)
        } else {
            add(feed, to: folderName)
        }
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
                presentStatus("Sources already loaded", message: "All seeded sources are already loaded.")
                isImportingPack = false
                return
            }
            Task {
                defer { isImportingPack = false }
                let freshRSS = SyncProvider.freshRSS.rawValue
                if let account = try? context.fetch(FetchDescriptor<SyncAccount>(predicate: #Predicate { $0.providerRawValue == freshRSS })).first,
                   account.isEnabled {
                    try? await FreshRSSSyncService().subscribeLocalFeeds(in: context)
                }
                do {
                    try await FeedService().refreshAll(in: context)
                    let restored = result.inserted
                    presentStatus(
                        "Restored \(restored) source\(restored == 1 ? "" : "s")",
                        message: "\(result.updated) updated."
                    )
                    reload()
                } catch {
                    presentStatus(
                        "Sources restored",
                        message: UserFacingFailure.shouldSurface(error)
                            ? UserFacingFailure.message(for: error, fallback: "The update did not finish.")
                            : "The update will finish on the next refresh."
                    )
                }
            }
        } catch {
            presentStatus("Couldn’t restore sources", message: UserFacingFailure.message(for: error, fallback: "Try again."))
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
                failures.append("\(input): \(UserFacingFailure.message(for: error, fallback: "Couldn’t add that source."))")
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
    var refreshError: String?
    var saveError: String?
    var removeError: String?
    private(set) var isRefreshing = false
    let progress = RefreshProgress()
    var availableFolders: [String] = []
    private(set) var isRemoving = false
    private var blockedWordsTask: Task<Void, Never>?
    private var pendingBlockedWords: String?
    private var membershipKeys: Set<String>?
    /// Builds of the folder membership set. A redraw does not increment this.
    private(set) var membershipBuilds = 0
    private var cachedRecentStories: [Article] = []
    /// Loads of the newest-twenty list. A redraw does not increment this.
    private(set) var recentStoryLoads = 0
    /// Fetches of every source, used to build the folder name list.
    private(set) var folderListLoads = 0
    private nonisolated(unsafe) var saveObserver: NSObjectProtocol?

    init(feed: Feed, context: ModelContext, freshRSSService: any FreshRSSSyncing = FreshRSSSyncService()) {
        self.feed = feed
        self.context = context
        self.freshRSSService = freshRSSService
        reloadFolders()
        reloadRecentStories()
        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: context,
            queue: nil
        ) { [weak self] note in
            MainActor.assumeIsolated {
                self?.noteStoreSaved(note)
            }
        }
    }

    deinit {
        if let saveObserver {
            NotificationCenter.default.removeObserver(saveObserver)
        }
    }

    func refresh() async {
        guard feed.refreshesOverRSS, !isRefreshing else { return }
        isRefreshing = true
        progress.begin(phase: .sources, total: 1)
        defer {
            reloadRecentStories()
            progress.finish()
            isRefreshing = false
        }
        await BackgroundRefreshCoordinator.runExclusive {
            do {
                try await FeedService().refresh(self.feed, in: self.context)
            } catch {
                self.refreshError = RefreshFailure.message(for: error, fallback: "Couldn’t refresh this source.")
            }
            self.progress.finishItem()
        }
    }

    func reloadFolders() {
        folderListLoads += 1
        let feeds = (try? context.fetch(FetchDescriptor<Feed>())) ?? []
        availableFolders = FolderStore.allNames(from: feeds)
    }

    func addFolder(_ name: String) {
        persist({ feed.addFolder(name) }, revert: { feed.removeFolder(name) })
        membershipKeys = nil
        reloadFolders()
    }

    func toggleFolder(_ name: String) {
        let wasMember = feed.containsFolder(name)
        persist({
            if wasMember {
                feed.removeFolder(name)
            } else {
                feed.addFolder(name)
            }
        }, revert: {
            if wasMember {
                feed.addFolder(name)
            } else {
                feed.removeFolder(name)
            }
        })
        membershipKeys = nil
    }

    /// Whether this source is in the folder. The set is built once until a folder check changes it.
    func sourceIsInFolder(_ name: String) -> Bool {
        guard let name = FeedMembership.normalized(name) else { return false }
        return currentMemberships().contains(name.lowercased())
    }

    private func currentMemberships() -> Set<String> {
        if let membershipKeys { return membershipKeys }
        membershipBuilds += 1
        let keys = Set(feed.memberships.map { $0.lowercased() })
        membershipKeys = keys
        return keys
    }

    var isEnabled: Bool {
        get { feed.isEnabled }
        set { updateTodayMembership { feed.isEnabled = newValue } }
    }
    var includeInToday: Bool {
        get { feed.includeInToday }
        set { updateTodayMembership { feed.includeInToday = newValue } }
    }

    private func updateTodayMembership(_ change: () -> Void) {
        let enabled = feed.isEnabled
        let included = feed.includeInToday
        change()
        LibraryChange.note(feed)
        do {
            try DailyDeckService.reconcileMembership(in: context)
        } catch {
            context.rollback()
            feed.isEnabled = enabled
            feed.includeInToday = included
            saveError = UserFacingFailure.message(for: error, fallback: "Couldn’t update that source.")
        }
    }

    var includeVideos: Bool {
        get { feed.includeVideos }
        set {
            let previous = feed.includeVideos
            persist({ feed.includeVideos = newValue }, revert: { feed.includeVideos = previous })
        }
    }
    var includeShorts: Bool {
        get { feed.includeShorts }
        set {
            let previous = feed.includeShorts
            persist({ feed.includeShorts = newValue }, revert: { feed.includeShorts = previous })
        }
    }
    var blockedWords: String {
        get { pendingBlockedWords ?? feed.blockedWords }
        set { scheduleBlockedWordsSave(newValue) }
    }

    /// Writes the words after typing pauses. Leaving the source writes immediately.
    func commitBlockedWords() {
        blockedWordsTask?.cancel()
        blockedWordsTask = nil
        guard let pending = pendingBlockedWords else { return }
        pendingBlockedWords = nil
        guard pending != feed.blockedWords else { return }
        let previous = feed.blockedWords
        feed.blockedWords = pending
        LibraryChange.note(feed)
        do {
            try context.save()
        } catch {
            feed.blockedWords = previous
            pendingBlockedWords = previous
            saveError = UserFacingFailure.message(for: error, fallback: "Couldn’t update that source.")
        }
    }

    private func persist(_ change: () -> Void, revert: () -> Void) {
        change()
        LibraryChange.note(feed)
        do {
            try context.save()
        } catch {
            revert()
            saveError = UserFacingFailure.message(for: error, fallback: "Couldn’t update that source.")
        }
    }

    private func scheduleBlockedWordsSave(_ value: String) {
        pendingBlockedWords = value
        blockedWordsTask?.cancel()
        blockedWordsTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            commitBlockedWords()
        }
    }

    @discardableResult
    func remove() async -> Bool {
        guard !isRemoving else { return false }
        isRemoving = true
        let showsLine = !progress.isActive
        if showsLine {
            progress.begin(phase: .sources, total: 1)
        }
        defer {
            if showsLine { progress.finish() }
            isRemoving = false
        }
        do {
            try await freshRSSService.removeSubscription(feed, in: context)
            if showsLine { progress.finishItem() }
            return true
        } catch {
            context.delete(feed)
            do {
                try context.save()
                LibraryChange.noteRemovedFeed(feed)
                if showsLine { progress.finishItem() }
                return true
            } catch {
                context.rollback()
                removeError = UserFacingFailure.message(for: error, fallback: "Couldn’t remove that source.")
                return false
            }
        }
    }

    /// The twenty newest stories. Typing and other redraws reuse this list.
    /// A saved insert or delete loads it again. A refresh loads it once when it finishes.
    var recentArticles: [Article] { cachedRecentStories }

    /// An article insert or delete changes the newest list. A title or setting save does not.
    private func noteStoreSaved(_ note: Notification) {
        guard !isRefreshing else { return }
        let inserted = Self.identifiers(note, .insertedIdentifiers)
        let deleted = Self.identifiers(note, .deletedIdentifiers)
        guard !inserted.isEmpty || !deleted.isEmpty else { return }
        reloadRecentStories()
    }

    private static func identifiers(_ note: Notification, _ key: ModelContext.NotificationKey) -> [PersistentIdentifier] {
        guard let value = note.userInfo?[key] else { return [] }
        if let set = value as? Set<PersistentIdentifier> { return Array(set) }
        if let list = value as? [PersistentIdentifier] { return list }
        return []
    }

    private func reloadRecentStories() {
        recentStoryLoads += 1
        cachedRecentStories = newestStories(limit: 20)
    }

    private func newestStories(limit: Int) -> [Article] {
        let feedID = feed.id
        var descriptor = ArticleListFetch.rows(
            predicate: #Predicate { $0.feed?.id == feedID },
            sortBy: [SortDescriptor(\.publishedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        if let stories = try? context.fetch(descriptor) { return stories }
        return Array(feed.articles.sorted { $0.publishedAt > $1.publishedAt }.prefix(limit))
    }
}
