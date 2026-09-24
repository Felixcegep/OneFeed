import SwiftData
import SwiftUI

private enum FeedToolbarDestination: Hashable, Identifiable {
    case sources, settings, history, folders
    var id: Self { self }
}

private struct FeedDayGroup: Identifiable {
    enum Kind: String {
        case today, yesterday, earlier
    }

    let kind: Kind
    let articles: [Article]
    var id: Kind { kind }

    var storedArticles: [Article] { articles.filter(\.isStored) }

    var title: String {
        switch kind {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .earlier: "Earlier"
        }
    }
}

struct FeedStreamView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Article> { $0.stateRawValue == "queued" || $0.stateRawValue == "current" },
        sort: \Article.publishedAt,
        order: .reverse
    ) private var articles: [Article]
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @State private var refresh = BrowseRefresh()
    @State private var selectedArticle: Article?
    @State private var search = ""
    @State private var selectedFolder: FeedFolderID?
    @State private var showingAddSource = false
    @State private var toolbarDestination: FeedToolbarDestination?

    private var folderSummaries: [FolderSummary] {
        FeedFolderGrouping.folderSummaries(feeds: feeds, articles: articles)
    }

    private var visible: [Article] {
        var open = FeedFolderGrouping.openArticles(from: articles)
        if let selectedFolder {
            let allowed = Set(feedsInFolder(selectedFolder).map(\.id))
            open = open.filter { article in
                guard let feedID = article.feed?.id else { return selectedFolder == .unfiled }
                return allowed.contains(feedID)
            }
        }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return open }
        return open.filter {
            $0.title.localizedStandardContains(query)
                || ($0.feed?.title.localizedStandardContains(query) ?? false)
                || ($0.displayExcerpt?.localizedStandardContains(query) ?? false)
        }
    }

    private var dayGroups: [FeedDayGroup] {
        Self.grouped(visible)
    }

    var body: some View {
        Group {
            if visible.isEmpty && folderSummaries.count <= 1 {
                EmptyLibraryState(
                    title: emptyTitle,
                    systemImage: search.isEmpty ? "sparkles" : "magnifyingglass",
                    description: emptyDescription,
                    actionTitle: search.isEmpty ? "Add a source" : nil,
                    action: search.isEmpty ? { showingAddSource = true } : nil
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        folderChips
                        if visible.isEmpty {
                            EmptyLibraryState(
                                title: emptyTitle,
                                systemImage: search.isEmpty ? "sparkles" : "magnifyingglass",
                                description: emptyDescription
                            )
                            .frame(maxWidth: .infinity, minHeight: 240)
                        } else {
                            ForEach(dayGroups) { group in
                                VStack(alignment: .leading, spacing: 10) {
                                    if dayGroups.count > 1 {
                                        Text(group.title)
                                            .font(OneFeedTheme.sansUI(13, weight: .semibold))
                                            .foregroundStyle(OneFeedTheme.graphite)
                                            .padding(.horizontal, 4)
                                            .accessibilityAddTraits(.isHeader)
                                    }
                                    VStack(spacing: 0) {
                                        ForEach(Array(group.storedArticles.enumerated()), id: \.element.id) { index, article in
                                            Button { selectedArticle = article } label: {
                                                ArticleRow(article: article)
                                            }
                                            .buttonStyle(DirectoryRowButtonStyle())
                                            .articleActions(for: article, in: modelContext)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(article.isCurrentReading ? OneFeedTheme.current : Color.clear)
                                            if index < group.storedArticles.count - 1 {
                                                Rectangle()
                                                    .fill(OneFeedTheme.plaster)
                                                    .frame(height: 8)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 6)
                                    .background(OneFeedTheme.paper, in: RoundedRectangle(cornerRadius: OneFeedTheme.cardRadius, style: .continuous))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, OneFeedTheme.pagePadding)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .clipped()
            }
        }
        .background(OneFeedTheme.plaster.ignoresSafeArea())
        .navigationTitle("Feed")
        .oneFeedLargeTitle()
        .oneFeedPaperToolbar()
        .oneFeedScrollEdge()
        .refreshProgressBanner(refresh.progress)
        .oneFeedSearchable($search, prompt: "Search articles")
        .toolbar {
            ToolbarItemGroup(placement: .oneFeedTrailing) {
                OneFeedToolbarRefresh(isRefreshing: refresh.isRefreshing) {
                    Task { await refresh.refresh(in: modelContext) }
                }
                Button("Add Source", systemImage: "plus") { showingAddSource = true }
                Menu {
                    Button("Sources", systemImage: "dot.radiowaves.left.and.right") {
                        toolbarDestination = .sources
                    }
                    Button("Settings", systemImage: "gearshape") {
                        toolbarDestination = .settings
                    }
                    Button("History", systemImage: "clock") {
                        toolbarDestination = .history
                    }
                    Button("Folders", systemImage: "folder") {
                        toolbarDestination = .folders
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
            }
        }
        .navigationDestination(item: $toolbarDestination) { destination in
            switch destination {
            case .sources: SourcesView()
            case .settings: SettingsView()
            case .history: HistoryView()
            case .folders: FoldersView()
            }
        }
        .refreshable { await refresh.refresh(in: modelContext) }
        .sheet(isPresented: $showingAddSource) {
            AddSourceView(onAdded: { Task { await refresh.refresh(in: modelContext) } })
        }
        .oneFeedArticleCover(item: $selectedArticle) { article in
            ReaderView(article: article) { state in
                selectedArticle = nil
                guard article.isStored else { return }
                ArticleActions.apply(state, to: article, in: modelContext)
            }
            .onAppear { LibrarySyncService.shared.hasActiveReadingSession = true }
            .onDisappear { LibrarySyncService.shared.hasActiveReadingSession = false }
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

    @ViewBuilder
    private var folderChips: some View {
        if folderSummaries.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("All", selected: selectedFolder == nil) {
                        selectedFolder = nil
                    }
                    ForEach(folderSummaries) { summary in
                        chip(
                            summary.name,
                            emoji: FolderEmoji.glyph(for: summary.name),
                            selected: selectedFolder == summary.folderID
                        ) {
                            selectedFolder = summary.folderID
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .padding(.bottom, 4)
        }
    }

    private func chip(_ title: String, emoji: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let emoji {
                    Text(emoji)
                        .font(.system(size: 16))
                }
                Text(title)
                    .font(OneFeedTheme.sansUI(15, weight: .medium))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(selected ? OneFeedTheme.ink : OneFeedTheme.paper, in: Capsule())
            .overlay {
                Capsule().strokeBorder(selected ? Color.clear : OneFeedTheme.sand, lineWidth: 1)
            }
            .foregroundStyle(selected ? OneFeedTheme.plaster : OneFeedTheme.ink)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var emptyTitle: String {
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "No matches" }
        if selectedFolder != nil { return "Nothing in this folder" }
        return "Nothing new"
    }

    private var emptyDescription: String {
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Try a source name or a different phrase."
        }
        if selectedFolder != nil {
            return "Stories from this folder will land here."
        }
        return "New stories from your sources will land here."
    }

    private func feedsInFolder(_ folderID: FeedFolderID) -> [Feed] {
        FeedFolderGrouping.groups(from: feeds).first(where: { $0.folderID == folderID })?.feeds ?? []
    }

    private static func grouped(_ articles: [Article], calendar: Calendar = .current) -> [FeedDayGroup] {
        var today: [Article] = []
        var yesterday: [Article] = []
        var earlier: [Article] = []
        for article in articles {
            if calendar.isDateInToday(article.publishedAt) {
                today.append(article)
            } else if calendar.isDateInYesterday(article.publishedAt) {
                yesterday.append(article)
            } else {
                earlier.append(article)
            }
        }
        return [
            FeedDayGroup(kind: .today, articles: today),
            FeedDayGroup(kind: .yesterday, articles: yesterday),
            FeedDayGroup(kind: .earlier, articles: earlier)
        ].filter { !$0.articles.isEmpty }
    }
}
