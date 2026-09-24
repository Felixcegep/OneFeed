import SwiftData
import SwiftUI

enum FeedBrowseDestination: Hashable {
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
    @Query(
        filter: #Predicate<Article> { $0.stateRawValue == "queued" || $0.stateRawValue == "current" },
        sort: \Article.publishedAt,
        order: .reverse
    ) private var openQuery: [Article]
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @State private var refresh = BrowseRefresh()
    @State private var showingAddSource = false
    @State private var toolbarDestination: FeedToolbarDestination?
    @State private var pickingFolder: FolderIconTarget?
    @State private var iconTick = 0
    @State private var isEditingFolders = false
    @State private var openFolderID: FeedFolderID?
    @State private var folderQuery = ""
    @State private var folderAddError: String?
    @State private var isAddingAddress = false
    @State private var showingNewFolder = false
    @State private var newFolderName = ""
    @State private var folderOrderTick = 0
    @State private var storyPlacements: [String: StoryPlacement] = [:]
    /// Folder rows stay put while refresh progress updates. Rebuilt only when sources, stories, or order change.
    @State private var directoryCache = FolderDirectoryCache()
    @FocusState private var focusedFolderName: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Full-screen cover only while refreshing with no folder rows and no articles yet.
    private var showsSourceRefreshCover: Bool {
        refresh.isRefreshing && feeds.isEmpty && openQuery.isEmpty && !isEditingFolders && !ReaderWebWarmup.skipsOpeningCover
    }

    var body: some View {
        let _ = iconTick
        let _ = folderOrderTick
        List {
            Section {
                if isEditingFolders {
                    if FeedFolderGrouping.groupsIncludingKnownEmpty(from: feeds).isEmpty {
                        emptySourceInvite
                    }
                    ForEach(editingRows) { row in
                        editingRow(row)
                    }
                    newFolderRow
                } else if directorySummaries.isEmpty {
                    emptySourceInvite
                } else {
                    ForEach(directorySummaries) { summary in
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
        .overlay {
            ZStack {
                if showsSourceRefreshCover {
                    OneFeedLoadingCover(
                        title: refresh.progress.primaryText,
                        status: refresh.progress.coverStatus,
                        canvas: OneFeedTheme.plaster
                    )
                    .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : OneFeedMotion.overlay, value: showsSourceRefreshCover)
        }
        .navigationTitle("Feed")
        .oneFeedLargeTitle()
        .oneFeedPaperToolbar()
        .oneFeedScrollEdge()
        .navigationSubtitle(refresh.statusText)
        .refreshProgressBanner(refresh.progress)
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
        .task {
            refresh.adoptLatestFetch(from: feeds)
            if ProcessInfo.processInfo.arguments.contains("-uiTestingNotInterested") {
                toolbarDestination = .notInterested
            }
        }
        .task(id: openQuery.map(\.id)) {
            storyPlacements = DailyDeckService.loadStoryPlacements(in: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: OneFeedNotify.storyIndexDidChange)) { _ in
            storyPlacements = DailyDeckService.loadStoryPlacements(in: modelContext)
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

    /// Cached folder rows. A progress tick keeps the same stamp, so the list is not regrouped.
    private var directorySummaries: [FolderSummary] {
        let stamp = directoryStampValue
        if directoryCache.stamp == stamp {
            return directoryCache.summaries
        }
        let summaries = FeedRootDirectory(
            feeds: feeds,
            articles: openQuery,
            placements: storyPlacements
        ).summaries
        directoryCache.stamp = stamp
        directoryCache.summaries = summaries
        return summaries
    }

    private var directoryStampValue: Int {
        var hasher = Hasher()
        hasher.combine(folderOrderTick)
        hasher.combine(placementStamp(storyPlacements))
        hasher.combine(openQuery.count)
        for article in openQuery {
            hasher.combine(article.id)
            hasher.combine(article.feed?.id)
        }
        for feed in feeds {
            hasher.combine(feed.id)
            hasher.combine(feed.memberships)
        }
        return hasher.finalize()
    }

    private func displayedFolderNames() -> [String] {
        FeedFolderGrouping.folderSummaries(feeds: feeds, articles: openQuery).compactMap { summary in
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
    private var editingRows: [SourceEditRow] {
        var rows: [SourceEditRow] = []
        let query = trimmedFolderQuery
        for group in FeedFolderGrouping.groupsIncludingKnownEmpty(from: feeds) {
            rows.append(.folder(group))
            guard openFolderID == group.folderID else { continue }
            for feed in group.feeds {
                rows.append(.source(feed, folderID: group.folderID))
            }
            guard case .named(let folderName) = group.folderID else { continue }
            for feed in folderSearchResults(in: folderName, query: query) {
                rows.append(.suggestion(feed, folderName: folderName))
            }
            if folderQueryIsAddress(query) {
                rows.append(.addURL(query: query, folderName: folderName))
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
        feed.removeFolder(folderName)
        LibraryChange.note(feed)
        try? modelContext.save()
    }

    private func fileExisting(_ feed: Feed, in folderName: String) {
        feed.addFolder(folderName)
        LibraryChange.note(feed)
        try? modelContext.save()
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
                if openFolderID == .named(folderName) {
                    folderAddError = RefreshFailure.message(for: error, fallback: "Couldn’t add that source.")
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

private func placementStamp(_ placements: [String: StoryPlacement]) -> Int {
    var stamp = placements.count
    for (key, placement) in placements {
        stamp ^= key.hashValue
        stamp ^= placement.relationshipRaw.hashValue
        stamp ^= placement.storyClusterID?.hashValue ?? 0
        stamp ^= placement.matchedConsumedAt?.hashValue ?? 0
    }
    return stamp
}

private final class StoryRowCache {
    var stamp = 0
    var rows: [FeedStoryRow] = []
}

private final class FolderDirectoryCache {
    var stamp = 0
    var summaries: [FolderSummary] = []
}

private struct FeedRootDirectory {
    let summaries: [FolderSummary]

    init(feeds: [Feed], articles: [Article], placements: [String: StoryPlacement] = [:]) {
        let open = FeedFolderGrouping.openArticles(from: articles)
        summaries = FeedFolderGrouping.folderSummaries(feeds: feeds, openArticles: open, placements: placements)
    }
}

struct ArticleCollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var articles: [Article]
    let destination: FeedBrowseDestination
    @State private var selectedArticle: Article?
    @State private var appliedSearch = ""
    @State private var expandedClusterIDs: Set<UUID> = []
    @State private var storyPlacements: [String: StoryPlacement] = [:]
    /// Story rows stay grouped while the open article changes. Rebuilt when the query, stories, or clusters change.
    @State private var storyRowCache = StoryRowCache()

    init(destination: FeedBrowseDestination) {
        self.destination = destination
        _articles = Query(
            filter: #Predicate<Article> { $0.stateRawValue == "queued" || $0.stateRawValue == "current" },
            sort: \Article.publishedAt,
            order: .reverse
        )
    }

    private var items: [Article] {
        let candidates: [Article] = switch destination {
        case .unread: FeedFolderGrouping.openArticles(from: articles)
        case .folder(let folderID):
            FeedFolderGrouping.folderArticleGroups(from: articles)
                .first(where: { $0.folderID == folderID })?
                .articles ?? []
        }
        let query = appliedSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return candidates }
        return candidates.filter {
            $0.title.localizedStandardContains(query)
                || ($0.feed?.title.localizedStandardContains(query) ?? false)
                || ($0.displayExcerpt?.localizedStandardContains(query) ?? false)
        }
    }

    private var storyRows: [FeedStoryRow] {
        let stamp = storyRowStamp
        if storyRowCache.stamp == stamp {
            return storyRowCache.rows
        }
        let rows = StoryGrouping.rows(
            from: items.filter(\.isStored),
            placements: storyPlacements,
            expandedClusterIDs: expandedClusterIDs
        )
        storyRowCache.stamp = stamp
        storyRowCache.rows = rows
        return rows
    }

    private var storyRowStamp: Int {
        var hasher = Hasher()
        hasher.combine(appliedSearch)
        hasher.combine(expandedClusterIDs)
        hasher.combine(placementStamp(storyPlacements))
        switch destination {
        case .unread: hasher.combine(0)
        case .folder(let id): hasher.combine(String(describing: id))
        }
        for article in articles where article.isStored {
            hasher.combine(article.id)
            hasher.combine(article.feed?.id)
            hasher.combine(article.stateRawValue)
        }
        return hasher.finalize()
    }

    var body: some View {
        OneFeedReadingSplit(article: $selectedArticle) {
            OneFeedSearchHost("Search articles", applied: $appliedSearch) {
                collectionColumn
            }
        } reader: { article in
            ReaderView(article: article, onFinish: { state in
                selectedArticle = nil
                guard article.isStored else { return }
                ArticleActions.apply(state, to: article, in: modelContext)
            }, onClose: {
                selectedArticle = nil
            })
            .onAppear { LibrarySyncService.shared.hasActiveReadingSession = true }
            .onDisappear { LibrarySyncService.shared.hasActiveReadingSession = false }
        }
        .readingUndoBanner()
    }

    private var collectionColumn: some View {
        Group {
            if storyRows.isEmpty {
                EmptyLibraryState(
                    title: emptyTitle,
                    systemImage: emptyImage,
                    description: emptyDescription
                )
            } else {
                List {
                    ForEach(storyRows) { row in
                        switch row.kind {
                        case .article(let article, let caption):
                            articleButton(article, caption: caption)
                        case .moreSources(let clusterID, let count):
                            moreSourcesButton(clusterID: clusterID, count: count)
                        }
                    }
                }
                .oneFeedGroupedListStyle()
            }
        }
        .navigationTitle(destination.title)
        .oneFeedLargeTitle()
        .oneFeedPaperToolbar()
        .oneFeedScrollEdge()
        .background(OneFeedTheme.plaster)
        .task(id: articles.map(\.id)) {
            storyPlacements = DailyDeckService.loadStoryPlacements(in: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: OneFeedNotify.storyIndexDidChange)) { _ in
            storyPlacements = DailyDeckService.loadStoryPlacements(in: modelContext)
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
        case .folder: "No unread stories in this folder."
        }
    }
}
