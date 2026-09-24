import SwiftData
import SwiftUI

/// Loads cluster captions away from the list, and skips the update when nothing changed.
private func refreshedStoryPlacements(
    from container: ModelContainer,
    current: [String: StoryPlacement]
) async -> [String: StoryPlacement]? {
    let placements = await DailyDeckService.loadStoryPlacements(from: container)
    guard !Task.isCancelled, placements != current else { return nil }
    return placements
}

enum FeedBrowseDestination: Hashable, Sendable {
    case unread
    case folder(FeedFolderID)

    var title: String {
        switch self {
        case .unread: String(localized: "New articles")
        case .folder(let id): id.title
        }
    }
}

struct FoldersView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var openQuery: [Article]

    init() {
        let queued = ArticleState.queued.rawValue
        let current = ArticleState.current.rawValue
        _openQuery = Query(ArticleListFetch.rows(
            predicate: #Predicate<Article> { article in
                article.stateRawValue == queued || article.stateRawValue == current
            },
            sortBy: [SortDescriptor(\.publishedAt, order: .reverse)]
        ))
    }
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @State private var refresh = BrowseRefresh()
    @State private var showingAddSource = false
    @State private var toolbarDestination: FeedToolbarDestination?
    @State private var pickingFolder: FolderIconTarget?
    @State private var iconTick = 0
    @State private var isEditingFolders = false
    @State private var openFolderID: FeedFolderID?
    @State private var folderQuery = ""
    @State private var appliedFolderQuery = ""
    @State private var folderAddError: String?
    @State private var sourceSaveError: String?
    @State private var isAddingAddress = false
    @State private var showingNewFolder = false
    @State private var newFolderName = ""
    @State private var folderOrderTick = 0
    @State private var storyPlacements: [String: StoryPlacement] = [:]
    @State private var placementTick = 0
    /// Folder rows stay put while refresh progress updates. Rebuilt off the main thread when sources, stories, or order change.
    @State private var folderSummaries: [FolderSummary] = []
    @State private var folderDirectoryReady = false
    @State private var editingFolderCache = EditingFolderCache()
    @FocusState private var focusedFolderName: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let _ = iconTick
        let _ = folderOrderTick
        let summaries = isEditingFolders ? [] : folderSummaries
        let editingGroups = isEditingFolders ? editingFolderCache.groups(from: feeds) : []
        return List {
            Section {
                if isEditingFolders {
                    if editingGroups.isEmpty {
                        emptySourceInvite
                    }
                    ForEach(editingRows(in: editingGroups)) { row in
                        editingRow(row)
                    }
                    newFolderRow
                } else if LibraryHold.showsExplanation(
                    hasStoredRows: !feeds.isEmpty,
                    ready: folderDirectoryReady,
                    hasPlannedRows: !summaries.isEmpty
                ) {
                    emptySourceInvite
                } else if !folderDirectoryReady {
                    Color.clear
                        .frame(height: 1)
                        .accessibilityHidden(true)
                } else {
                    ForEach(summaries) { summary in
                        folderRow(summary)
                    }
                }
                editFoldersRow
            } header: {
                GallerySectionHeader(text: "Folders")
            }
            Section {
                NavigationLink {
                    ArticleCollectionView(destination: .unread)
                } label: {
                    FeedDirectoryRow(title: "New articles", systemImage: "text.alignleft", detail: "From all your sources")
                }
                .oneFeedDirectoryRow()
            }
        }
        .oneFeedGroupedListStyle()
        .debouncedSearch(folderQuery, into: $appliedFolderQuery)
        .modifier(FeedListRefreshChrome(
            refresh: refresh,
            hasSources: !feeds.isEmpty,
            hasArticles: !openQuery.isEmpty,
            isEditing: isEditingFolders,
            reduceMotion: reduceMotion
        ))
        .navigationTitle("Feed")
        .oneFeedLargeTitle()
        .oneFeedPaperToolbar()
        .oneFeedScrollEdge()
        .navigationSubtitle(refresh.statusText)
        .toolbar {
            ToolbarItem(placement: .oneFeedPinnedTrailing) {
                Button("Add Source", systemImage: "plus") { showingAddSource = true }
            }
            ToolbarItem(placement: .oneFeedTrailing) {
                NavigationLink {
                    SourcesView()
                } label: {
                    Image(systemName: "dot.radiowaves.left.and.right")
                }
                .accessibilityLabel("Sources")
            }
        }
        .navigationDestination(item: $toolbarDestination) { destination in
            switch destination {
            case .notInterested: NotInterestedView()
            }
        }
        .refreshable { await refresh.refresh(in: modelContext) }
        .onAppear { refresh.noteVisibleDay() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh.noteVisibleDay() }
        }
        .task {
            refresh.adoptLatestFetch(from: feeds)
            if ProcessInfo.processInfo.arguments.contains("-uiTestingNotInterested") {
                toolbarDestination = .notInterested
            }
        }
        .task(id: openQueryEdge) {
            await reloadStoryPlacements()
        }
        .task(id: directoryEdge) {
            await reloadFolderSummaries()
        }
        .onReceive(NotificationCenter.default.publisher(for: OneFeedNotify.storyIndexDidChange)) { _ in
            Task { await reloadStoryPlacements() }
        }
        .sheet(isPresented: $showingAddSource) {
            AddSourceView(onAdded: { Task { await refresh.refresh(in: modelContext) } })
        }
        .sheet(item: $pickingFolder) { target in
            FolderEmojiPicker(folderName: target.name) { _ in
                iconTick += 1
            }
        }
        .alert("New Folder", isPresented: $showingNewFolder) {
            TextField("Must read, Builders…", text: $newFolderName)
            Button("Cancel", role: .cancel) { newFolderName = "" }
            Button("Create") { createFolder() }
        } message: {
            Text("Folders group sources. Add feeds into it next.")
        }
        .alert("Couldn’t refresh", isPresented: Binding(
            get: { refresh.presentedError != nil },
            set: { if !$0 { refresh.presentedError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(refresh.presentedError ?? "")
        }
        .alert("Couldn’t update that source", isPresented: Binding(
            get: { sourceSaveError != nil },
            set: { if !$0 { sourceSaveError = nil } }
        )) {
            Button("OK", role: .cancel) { sourceSaveError = nil }
        } message: {
            Text(sourceSaveError ?? "")
        }
    }

    private func reloadStoryPlacements() async {
        guard let placements = await refreshedStoryPlacements(from: modelContext.container, current: storyPlacements) else { return }
        storyPlacements = placements
        placementTick &+= 1
    }

    private func folderRow(_ summary: FolderSummary) -> some View {
        let canReorder = summary.folderID != .unfiled
        return HStack(spacing: 4) {
            FolderEmojiButton(name: summary.name) {
                pickingFolder = FolderIconTarget(name: summary.name)
            }
            NavigationLink {
                ArticleCollectionView(destination: .folder(summary.folderID))
            } label: {
                FeedDirectoryRow(
                    title: summary.name,
                    count: summary.unreadCount
                )
            }
        }
        .accessibilityIdentifier("folder-\(summary.name)")
        .oneFeedDirectoryRow()
        .accessibilityActions {
            if canReorder {
                Button("Move up") { moveFolder(summary.name, by: -1) }
                Button("Move down") { moveFolder(summary.name, by: 1) }
            }
        }
        .contextMenu {
            Button("Change icon", systemImage: "face.smiling") {
                pickingFolder = FolderIconTarget(name: summary.name)
            }
            if canReorder {
                Button("Move up", systemImage: "arrow.up") { moveFolder(summary.name, by: -1) }
                Button("Move down", systemImage: "arrow.down") { moveFolder(summary.name, by: 1) }
            }
        }
    }

    private func reloadFolderSummaries() async {
        let edge = directoryEdge
        let feedSnaps = feeds.map { FolderFeedSnap(id: $0.id, memberships: $0.memberships) }
        let storySnaps = openQuery.map { article in
            FolderStorySnap(
                feedID: article.feed?.id,
                publishedAt: article.publishedAt,
                videoID: article.videoID,
                url: article.url,
                guid: article.guid,
                id: article.id,
                hasRemoteID: article.remoteID != nil,
                stateRaw: article.stateRawValue,
                isRemoteStarred: article.isRemoteStarred
            )
        }
        let placements = storyPlacements
        let order = FolderStore.knownNames()
        let summaries = await Task.detached(priority: .userInitiated) {
            FolderDirectoryCount.summaries(
                feeds: feedSnaps,
                stories: storySnaps,
                placements: placements,
                folderOrder: order
            )
        }.value
        guard !Task.isCancelled, edge == directoryEdge else { return }
        folderSummaries = summaries
        folderDirectoryReady = true
    }

    /// Every open story, plus each source. A refresh tick does not regroup the folders.
    private var directoryEdge: Int {
        var token = folderOrderTick
        token = token &* 31 &+ openQueryEdge
        token = token &* 31 &+ placementTick
        for feed in feeds {
            token = token &* 31 &+ feed.id.hashValue
            token = token &* 31 &+ feed.memberships.hashValue
            token = token &* 31 &+ (feed.isEnabled ? 1 : 0)
        }
        return token
    }

    private var openQueryEdge: Int {
        ListIdentity.token(ids: openQuery.lazy.map(\.id))
    }

    /// The folders already on screen. Moving one does not count every open story again.
    private func displayedFolderNames() -> [String] {
        folderSummaries.compactMap { summary in
            if case .named(let name) = summary.folderID { return name }
            return nil
        }
    }

    private func moveFolder(_ source: String, by offset: Int) {
        let names = displayedFolderNames()
        guard let index = names.firstIndex(where: { $0.caseInsensitiveCompare(source) == .orderedSame }) else { return }
        let destination = index + offset
        guard names.indices.contains(destination) else { return }
        moveFolder(source, onto: names[destination])
    }

    private func moveFolder(_ source: String, onto target: String) {
        guard source.caseInsensitiveCompare(target) != .orderedSame else { return }
        var names = displayedFolderNames()
        guard let from = names.firstIndex(where: { $0.caseInsensitiveCompare(source) == .orderedSame }),
              let to = names.firstIndex(where: { $0.caseInsensitiveCompare(target) == .orderedSame }) else { return }
        let item = names.remove(at: from)
        names.insert(item, at: to)
        withAnimation(reduceMotion ? nil : OneFeedMotion.list) {
            FolderStore.setOrder(names)
            folderOrderTick += 1
        }
    }

    private var editFoldersRow: some View {
        Button(isEditingFolders ? "Finish editing" : "Edit folders") {
            toggleEditing()
        }
        .font(.body)
        .foregroundStyle(OneFeedTheme.graphite)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .accessibilityHint(isEditingFolders ? "Leaves folder editing" : "Shows empty folders and lets you file sources")
        .oneFeedDirectoryRow()
    }

    private var emptySourceInvite: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bring your favorite publications together.")
                .font(.subheadline)
                .foregroundStyle(OneFeedTheme.graphite)
            Button("Add a source", systemImage: "plus") {
                showingAddSource = true
            }
            .buttonStyle(DecisionActionStyle(expands: false))
        }
        .padding(.vertical, 12)
        .oneFeedDirectoryRow()
    }

    private var newFolderRow: some View {
        Button {
            newFolderName = ""
            showingNewFolder = true
        } label: {
            FeedDirectoryRow(title: "New Folder", systemImage: "folder.badge.plus")
        }
        .buttonStyle(.plain)
        .oneFeedDirectoryRow()
    }

    private var trimmedFolderQuery: String {
        folderQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Occupied folders, plus remembered empty ones, with the open folder's sources and add field.
    private func editingRows(in groups: [FeedFolderGroup]) -> [SourceEditRow] {
        var rows: [SourceEditRow] = []
        let live = trimmedFolderQuery
        let query = appliedFolderQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        for group in groups {
            rows.append(.folder(group))
            guard openFolderID == group.folderID else { continue }
            for feed in group.feeds {
                rows.append(.source(feed, folderID: group.folderID))
            }
            guard case .named(let folderName) = group.folderID else { continue }
            for feed in folderSearchResults(in: folderName, query: query) {
                rows.append(.suggestion(feed, folderName: folderName))
            }
            if folderQueryIsAddress(live) {
                rows.append(.addURL(query: live, folderName: folderName))
            }
            rows.append(.field(folderName))
            if let folderAddError {
                rows.append(.failure(folderAddError))
            }
        }
        return rows
    }

    @ViewBuilder
    private func editingRow(_ row: SourceEditRow) -> some View {
        switch row {
        case .folder(let group):
            editingFolderHeader(group)
        case .source(let feed, let folderID):
            editingSourceRow(feed, folderID: folderID)
        case .field(let folderName):
            folderQueryField(folderName)
        case .failure(let message):
            Text(message)
                .font(.subheadline)
                .foregroundStyle(OneFeedTheme.error)
                .frame(maxWidth: .infinity, alignment: .leading)
                .oneFeedDirectoryRow()
        case .suggestion(let feed, let folderName):
            suggestionRow(feed, folderName: folderName)
        case .addURL(let query, let folderName):
            addAddressRow(query: query, folderName: folderName)
        }
    }

    private func editingFolderHeader(_ group: FeedFolderGroup) -> some View {
        let isOpen = openFolderID == group.folderID
        return HStack(spacing: 4) {
            FolderEmojiButton(name: group.name) {
                pickingFolder = FolderIconTarget(name: group.name)
            }
            Button {
                toggleFolder(group.folderID)
            } label: {
                HStack(spacing: 8) {
                    FeedDirectoryRow(title: group.name)
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(OneFeedTheme.graphite)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(group.name)
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
            .accessibilityHint(isOpen ? "Collapses this folder" : "Shows the sources in this folder")
        }
        .oneFeedDirectoryRow()
        .contextMenu {
            Button("Change icon", systemImage: "face.smiling") {
                pickingFolder = FolderIconTarget(name: group.name)
            }
        }
    }

    private func editingSourceRow(_ feed: Feed, folderID: FeedFolderID) -> some View {
        HStack(spacing: 8) {
            if case .named(let folderName) = folderID {
                Button {
                    removeFromFolder(feed, folderName: folderName)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.body)
                        .foregroundStyle(OneFeedTheme.error)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(feed.title) from \(folderName)")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(feed.title)
                    .font(.body)
                    .foregroundStyle(OneFeedTheme.ink)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
                if case .named(let folderName) = folderID, let alsoIn = feed.alsoInLine(excluding: folderName) {
                    Text(alsoIn)
                        .font(.subheadline)
                        .foregroundStyle(OneFeedTheme.graphite)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .oneFeedDirectoryRow()
    }

    private func folderQueryField(_ folderName: String) -> some View {
        TextField("Search sources or paste a URL", text: $folderQuery)
            .font(.body)
            .foregroundStyle(OneFeedTheme.ink)
            .textFieldStyle(.plain)
            .oneFeedAutocapitalizationNever()
            .autocorrectionDisabled()
            .focused($focusedFolderName, equals: folderName)
            .onAppear { focusedFolderName = folderName }
            .onSubmit {
                let query = trimmedFolderQuery
                guard folderQueryIsAddress(query) else { return }
                addAddress(query, to: folderName)
            }
            .oneFeedDirectoryRow()
    }

    private func suggestionRow(_ feed: Feed, folderName: String) -> some View {
        Button {
            fileExisting(feed, in: folderName)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(feed.title)
                    .font(.body)
                    .foregroundStyle(OneFeedTheme.ink)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(feed.filedInLine)
                    .font(.subheadline)
                    .foregroundStyle(OneFeedTheme.graphite)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .oneFeedDirectoryRow()
    }

    private func addAddressRow(query: String, folderName: String) -> some View {
        Button {
            addAddress(query, to: folderName)
        } label: {
            Text("Add \(query) to \(folderName)")
                .font(.body)
                .foregroundStyle(OneFeedTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(isAddingAddress)
        .oneFeedDirectoryRow()
    }

    private func folderSearchResults(in folderName: String, query: String) -> [Feed] {
        guard !query.isEmpty else { return [] }
        var matches: [Feed] = []
        matches.reserveCapacity(8)
        for feed in feeds where !feed.containsFolder(folderName) && feedMatches(feed, query: query) {
            matches.append(feed)
            if matches.count == 8 { break }
        }
        return matches
    }

    private func feedMatches(_ feed: Feed, query: String) -> Bool {
        if feed.title.localizedStandardContains(query) { return true }
        if feed.feedURL.absoluteString.localizedStandardContains(query) { return true }
        if let website = feed.websiteURL?.absoluteString, website.localizedStandardContains(query) { return true }
        return false
    }

    /// A pasted address, not a search word. `FeedService.normalizedURL` is not used: it turns any word into https://word.
    private func folderQueryIsAddress(_ query: String) -> Bool {
        guard !query.isEmpty else { return false }
        if query.contains("://") { return true }
        if query.lowercased().hasPrefix("feed:") { return true }
        return query.contains(".") && !query.contains(where: \.isWhitespace)
    }

    private func toggleEditing() {
        animate {
            isEditingFolders.toggle()
            if !isEditingFolders {
                openFolderID = nil
                folderQuery = ""
                folderAddError = nil
                focusedFolderName = nil
            }
        }
    }

    private func toggleFolder(_ folderID: FeedFolderID) {
        animate {
            if openFolderID == folderID {
                openFolderID = nil
                focusedFolderName = nil
            } else {
                openFolderID = folderID
                if case .named(let name) = folderID {
                    focusedFolderName = name
                } else {
                    focusedFolderName = nil
                }
            }
            folderQuery = ""
            folderAddError = nil
        }
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        newFolderName = ""
        guard !name.isEmpty else { return }
        FolderStore.remember(name)
        LibraryChange.noteStructureChanged()
        let canonical = FolderStore.knownNames().first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name
        animate {
            isEditingFolders = true
            openFolderID = .named(canonical)
            folderQuery = ""
            folderAddError = nil
        }
        focusedFolderName = canonical
    }

    private func removeFromFolder(_ feed: Feed, folderName: String) {
        guard feed.removeFolder(folderName) else { return }
        LibraryChange.note(feed)
        do {
            try modelContext.save()
        } catch {
            feed.addFolder(folderName)
            sourceSaveError = UserFacingFailure.message(for: error, fallback: "Couldn’t update that source.")
        }
    }

    private func fileExisting(_ feed: Feed, in folderName: String) {
        guard feed.addFolder(folderName) else { return }
        LibraryChange.note(feed)
        do {
            try modelContext.save()
        } catch {
            feed.removeFolder(folderName)
            sourceSaveError = UserFacingFailure.message(for: error, fallback: "Couldn’t update that source.")
            return
        }
        folderQuery = ""
        folderAddError = nil
    }

    private func addAddress(_ query: String, to folderName: String) {
        guard !isAddingAddress else { return }
        isAddingAddress = true
        folderAddError = nil
        Task {
            do {
                let freshRSS = SyncProvider.freshRSS.rawValue
                let account = try? modelContext.fetch(
                    FetchDescriptor<SyncAccount>(predicate: #Predicate { $0.providerRawValue == freshRSS })
                ).first
                if account?.isEnabled == true, !FeedService.importsWithoutRSS(query) {
                    _ = try await FreshRSSSyncService().addSubscription(from: query, folderName: folderName, in: modelContext)
                } else {
                    _ = try await FeedService().addSource(from: query, folderName: folderName, in: modelContext)
                }
                if openFolderID == .named(folderName) {
                    folderQuery = ""
                }
                folderAddError = nil
            } catch {
                let message = RefreshFailure.message(for: error, fallback: "Couldn’t add that source.")
                if openFolderID == .named(folderName) {
                    folderAddError = message
                } else {
                    sourceSaveError = message
                }
            }
            isAddingAddress = false
        }
    }

    private func animate(_ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(OneFeedMotion.list, updates)
        }
    }
}

/// Editing rows reuse folder groups until a source or a remembered folder name changes.
private final class EditingFolderCache {
    private var edge = Int.min
    private var cached: [FeedFolderGroup] = []

    func groups(from feeds: [Feed]) -> [FeedFolderGroup] {
        let next = Self.edge(of: feeds)
        if next == edge { return cached }
        cached = FeedFolderGrouping.groupsIncludingKnownEmpty(from: feeds)
        edge = next
        return cached
    }

    private static func edge(of feeds: [Feed]) -> Int {
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
}

private enum SourceEditRow: Identifiable {
    case folder(FeedFolderGroup)
    case source(Feed, folderID: FeedFolderID)
    case suggestion(Feed, folderName: String)
    case addURL(query: String, folderName: String)
    case field(String)
    case failure(String)

    var id: String {
        switch self {
        case .folder(let group):
            "folder-\(Self.key(group.folderID))"
        case .source(let feed, let folderID):
            "source-\(Self.key(folderID))-\(feed.id.uuidString)"
        case .suggestion(let feed, let folderName):
            "suggestion-\(folderName)-\(feed.id.uuidString)"
        case .addURL(let query, let folderName):
            "add-\(folderName)-\(query)"
        case .field(let folderName):
            "field-\(folderName)"
        case .failure(let message):
            "failure-\(message)"
        }
    }

    private static func key(_ folderID: FeedFolderID) -> String {
        switch folderID {
        case .named(let name): name
        case .unfiled: "unfiled"
        }
    }
}

private enum FeedToolbarDestination: Hashable, Identifiable {
    case notInterested
    var id: Self { self }
}

/// Progress ticks stay on this chrome. The folder list does not read the progress line, so a refresh does not rebuild the rows.
private struct FeedListRefreshChrome: ViewModifier {
    var refresh: BrowseRefresh
    var hasSources: Bool
    var hasArticles: Bool
    var isEditing: Bool
    var reduceMotion: Bool

    private var showsCover: Bool {
        refresh.isRefreshing && !hasSources && !hasArticles && !isEditing && !ReaderWebWarmup.skipsOpeningCover
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    if showsCover {
                        OneFeedLoadingCover(
                            title: refresh.progress.primaryText,
                            status: refresh.progress.coverStatus,
                            canvas: OneFeedTheme.plaster
                        )
                        .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : OneFeedMotion.overlay, value: showsCover)
            }
            .refreshProgressBanner(refresh.progress)
    }
}

/// Progress ticks stay on this chrome. The story list does not read the progress line, so a refresh does not regroup the rows.
private struct StoryListRefreshChrome: ViewModifier {
    var refresh: BrowseRefresh
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content
            .refreshProgressBanner(refresh.progress)
            .toolbar {
                ToolbarItem(placement: .oneFeedTrailing) {
                    OneFeedToolbarRefresh(isRefreshing: refresh.isRefreshing) {
                        Task { await refresh.refresh(in: modelContext) }
                    }
                }
            }
    }
}

struct ArticleCollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var articles: [Article]
    @Query(sort: \Feed.title) private var feeds: [Feed]
    let destination: FeedBrowseDestination
    @State private var selectedArticle: Article?
    @State private var storyError: String?
    @State private var appliedSearch = ""
    @State private var expandedClusterIDs: Set<UUID> = []
    @State private var storyPlacements: [String: StoryPlacement] = [:]
    @State private var placementTick = 0
    /// Story rows stay grouped while the open article changes. Rebuilt off the main thread when the query, stories, or clusters change.
    @State private var displayedStoryRows: [FeedStoryRow] = []
    @State private var storyListReady = false
    @State private var refresh = BrowseRefresh()

    init(destination: FeedBrowseDestination) {
        self.destination = destination
        let queued = ArticleState.queued.rawValue
        let current = ArticleState.current.rawValue
        _articles = Query(ArticleListFetch.rows(
            predicate: #Predicate<Article> { article in
                article.stateRawValue == queued || article.stateRawValue == current
            },
            sortBy: [SortDescriptor(\.publishedAt, order: .reverse)]
        ))
    }

    private func reloadStoryList() async {
        let edge = storyEdge
        let destination = destination
        let feedsByID = Dictionary(feeds.map { ($0.id, FolderFeedSnap(id: $0.id, memberships: $0.memberships)) }, uniquingKeysWith: { first, _ in first })
        let query = appliedSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let searching = !query.isEmpty
        let snaps = articles.map { article in
            StoryListSnap(
                id: article.id,
                feedID: article.feed?.id,
                feedTitle: searching ? article.feed?.title : nil,
                publishedAt: article.publishedAt,
                title: searching ? article.title : "",
                aiSummary: query.isEmpty ? nil : ContentClassifier.cardExcerptSample(article.aiSummary),
                summary: query.isEmpty ? nil : ContentClassifier.cardExcerptSample(article.summary),
                videoID: article.videoID,
                url: article.url,
                guid: article.guid,
                hasRemoteID: article.remoteID != nil,
                stateRaw: article.stateRawValue,
                isRemoteStarred: article.isRemoteStarred
            )
        }
        let placements = storyPlacements
        let expanded = expandedClusterIDs
        let now = Date()
        let plans = await Task.detached(priority: .userInitiated) {
            StoryListPlan.rows(
                destination: destination,
                feeds: feedsByID,
                stories: snaps,
                placements: placements,
                expanded: expanded,
                query: query,
                now: now
            )
        }.value
        guard !Task.isCancelled, edge == storyEdge else { return }
        let byID = Dictionary(articles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        displayedStoryRows = plans.compactMap { plan in
            switch plan.kind {
            case .article(let id, let caption):
                guard let article = byID[id], article.isStored else { return nil }
                return FeedStoryRow(id: plan.id, kind: .article(article, caption: caption))
            case .moreSources(let clusterID, let count):
                return FeedStoryRow(id: plan.id, kind: .moreSources(clusterID: clusterID, count: count))
            }
        }
        storyListReady = true
    }

    /// Search, expansion, and every story id. Opening a story does not regroup the rows.
    private func reloadStoryPlacements() async {
        guard let placements = await refreshedStoryPlacements(from: modelContext.container, current: storyPlacements) else { return }
        storyPlacements = placements
        placementTick &+= 1
    }

    private var storyEdge: Int {
        var token = appliedSearch.hashValue
        token = token &* 31 &+ articleEdge
        token = token &* 31 &+ placementTick
        token = token &* 31 &+ expandedClusterIDs.count
        switch destination {
        case .unread: token = token &* 31 &+ 1
        case .folder(let id): token = token &* 31 &+ String(describing: id).hashValue
        }
        for id in expandedClusterIDs {
            token ^= id.hashValue
        }
        for feed in feeds {
            token = token &* 31 &+ feed.id.hashValue
            token = token &* 31 &+ feed.memberships.hashValue
        }
        return token
    }

    private var articleEdge: Int {
        ListIdentity.token(ids: articles.lazy.map(\.id))
    }

    var body: some View {
        OneFeedReadingSplit(article: $selectedArticle) {
            OneFeedSearchHost("Search articles", applied: $appliedSearch) {
                collectionColumn
            }
        } reader: { article in
            ReaderView(article: article, onFinish: { state in
                guard article.isStored else {
                    selectedArticle = nil
                    return true
                }
                do {
                    try ArticleActions.apply(state, to: article, in: modelContext)
                } catch {
                    storyError = UserFacingFailure.message(for: error, fallback: "Couldn’t update that story.")
                    return false
                }
                selectedArticle = nil
                return true
            }, onClose: {
                selectedArticle = nil
            })
            .onAppear { LibrarySyncService.shared.hasActiveReadingSession = true }
            .onDisappear { LibrarySyncService.shared.hasActiveReadingSession = false }
        }
        .readingUndoBanner()
        .alert("Couldn’t update that story", isPresented: Binding(
            get: { storyError != nil },
            set: { if !$0 { storyError = nil } }
        )) {
            Button("OK", role: .cancel) { storyError = nil }
        } message: {
            Text(storyError ?? "")
        }
    }

    private var collectionColumn: some View {
        Group {
            if LibraryHold.showsExplanation(
                hasStoredRows: articles.contains(where: \.isStored),
                ready: storyListReady,
                hasPlannedRows: !displayedStoryRows.isEmpty
            ) {
                EmptyLibraryState(
                    title: emptyTitle,
                    systemImage: emptyImage,
                    description: emptyDescription,
                    actionTitle: appliedSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Refresh" : nil,
                    action: appliedSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? { Task { await refresh.refresh(in: modelContext) } }
                        : nil
                )
            } else if !storyListReady {
                Color.clear
                    .frame(height: 1)
                    .accessibilityHidden(true)
            } else {
                List {
                    ForEach(displayedStoryRows) { row in
                        switch row.kind {
                        case .article(let article, let caption):
                            articleButton(article, caption: caption)
                        case .moreSources(let clusterID, let count):
                            moreSourcesButton(clusterID: clusterID, count: count)
                        }
                    }
                }
                .oneFeedGroupedListStyle()
                .refreshable { await refresh.refresh(in: modelContext) }
            }
        }
        .navigationTitle(destination.title)
        .oneFeedLargeTitle()
        .oneFeedPaperToolbar()
        .oneFeedScrollEdge()
        .background(OneFeedTheme.plaster)
        .modifier(StoryListRefreshChrome(refresh: refresh))
        .task { refresh.adoptLatestFetch(from: feeds) }
        .alert("Couldn’t refresh", isPresented: Binding(
            get: { refresh.presentedError != nil },
            set: { if !$0 { refresh.presentedError = nil } }
        )) {
            Button("OK", role: .cancel) { refresh.presentedError = nil }
        } message: {
            Text(refresh.presentedError ?? "")
        }
        .task(id: articleEdge) {
            await reloadStoryPlacements()
        }
        .task(id: storyEdge) {
            await reloadStoryList()
        }
        .onReceive(NotificationCenter.default.publisher(for: OneFeedNotify.storyIndexDidChange)) { _ in
            Task { await reloadStoryPlacements() }
        }
    }

    private func articleButton(_ article: Article, caption: String?) -> some View {
        Button { selectedArticle = article } label: {
            ArticleRow(article: article, status: caption)
        }
        .buttonStyle(DirectoryRowButtonStyle())
        .articleListRow(isCurrent: article.isCurrentReading, isSelected: selectedArticle?.id == article.id)
        .articleActions(for: article, in: modelContext)
    }

    private func moreSourcesButton(clusterID: UUID, count: Int) -> some View {
        let title = StoryGrouping.moreSourcesTitle(count: count)
        return Button {
            if expandedClusterIDs.contains(clusterID) {
                expandedClusterIDs.remove(clusterID)
            } else {
                expandedClusterIDs.insert(clusterID)
            }
        } label: {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(OneFeedTheme.graphite)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(DirectoryRowButtonStyle())
        .articleListRow()
        .accessibilityLabel(title)
        .accessibilityValue(expandedClusterIDs.contains(clusterID) ? "Expanded" : "Collapsed")
        .accessibilityHint(expandedClusterIDs.contains(clusterID) ? "Hides the other sources" : "Shows the other sources")
    }

    private var emptyTitle: String {
        if !appliedSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "No matches" }
        return switch destination {
        case .unread: "You're caught up"
        case .folder: "Caught up"
        }
    }

    private var emptyImage: String {
        if !appliedSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "magnifyingglass" }
        return switch destination {
        case .unread: "checkmark.circle"
        case .folder: "checkmark.circle"
        }
    }

    private var emptyDescription: String {
        if !appliedSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Try a different title or source name." }
        return switch destination {
        case .unread: "New stories from your sources will land here."
        case .folder: "New stories from this folder will land here."
        }
    }
}
