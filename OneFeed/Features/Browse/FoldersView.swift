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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsSourceRefreshCover: Bool {
        refresh.isRefreshing && !ReaderWebWarmup.skipsOpeningCover
    }

    var body: some View {
        let directory = FeedRootDirectory(feeds: feeds, articles: openQuery)
        let _ = iconTick
        List {
            Section {
                NavigationLink {
                    ArticleCollectionView(destination: .unread)
                } label: {
                    FeedDirectoryRow(title: "New articles", systemImage: "text.alignleft", detail: "From all your sources")
                }
                .oneFeedDirectoryRow()
            } header: {
                GallerySectionHeader(text: "Browse")
            }
            Section {
                NavigationLink {
                    SourcesView()
                } label: {
                    FeedDirectoryRow(
                        title: "Manage sources",
                        systemImage: "dot.radiowaves.left.and.right",
                        detail: "Add, move, or pause subscriptions"
                    )
                }
                .oneFeedDirectoryRow()
                if directory.summaries.isEmpty {
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
                } else {
                    ForEach(directory.summaries) { summary in
                        folderRow(summary)
                    }
                }
            } header: {
                GallerySectionHeader(text: "Your sources")
            }
        }
        .oneFeedGroupedListStyle()
        .overlay {
            if showsSourceRefreshCover {
                OneFeedLoadingCover(
                    title: refresh.progress.primaryText,
                    status: refresh.progress.coverStatus,
                    canvas: OneFeedTheme.plaster
                )
            }
        }
        .animation(reduceMotion ? nil : OneFeedMotion.overlay, value: showsSourceRefreshCover)
        .navigationTitle("Feed")
        .oneFeedLargeTitle()
        .oneFeedPaperToolbar()
        .navigationSubtitle(refresh.statusText)
        .refreshProgressBanner(refresh.progress)
        .toolbar {
            ToolbarItem(placement: .oneFeedTrailing) {
                OneFeedToolbarRefresh(isRefreshing: refresh.isRefreshing) {
                    Task { await refresh.refresh(in: modelContext) }
                }
            }
            .visibilityPriority(.high)
            ToolbarItem(placement: .oneFeedPinnedTrailing) {
                Button("Add Source", systemImage: "plus") { showingAddSource = true }
            }
            .visibilityPriority(.high)
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
        .sheet(isPresented: $showingAddSource) { AddSourceView() }
        .sheet(item: $pickingFolder) { target in
            FolderEmojiPicker(folderName: target.name) { _ in
                iconTick += 1
            }
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
        HStack(spacing: 4) {
            FolderEmojiButton(name: summary.name) {
                pickingFolder = FolderIconTarget(name: summary.name)
            }
            NavigationLink {
                ArticleCollectionView(destination: .folder(summary.folderID))
            } label: {
                FeedDirectoryRow(
                    title: summary.name
                )
            }
        }
        .accessibilityIdentifier("folder-\(summary.name)")
        .accessibilityElement(children: .contain)
        .oneFeedDirectoryRow()
        .contextMenu {
            Button("Change icon", systemImage: "face.smiling") {
                pickingFolder = FolderIconTarget(name: summary.name)
            }
        }
    }
}

private enum FeedToolbarDestination: Hashable, Identifiable {
    case notInterested
    var id: Self { self }
}

private struct FeedRootDirectory {
    let summaries: [FolderSummary]

    init(feeds: [Feed], articles: [Article]) {
        let open = FeedFolderGrouping.openArticles(from: articles)
        summaries = FeedFolderGrouping.folderSummaries(feeds: feeds, openArticles: open)
    }
}

struct ArticleCollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var articles: [Article]
    let destination: FeedBrowseDestination
    @State private var selectedArticle: Article?
    @State private var searchText = ""

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
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return candidates }
        return candidates.filter {
            $0.title.localizedStandardContains(query)
                || ($0.feed?.title.localizedStandardContains(query) ?? false)
                || ($0.displayExcerpt?.localizedStandardContains(query) ?? false)
        }
    }

    var body: some View {
        OneFeedReadingSplit(article: $selectedArticle) {
            collectionColumn
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
    }

    private var collectionColumn: some View {
        Group {
            if items.isEmpty {
                EmptyLibraryState(
                    title: emptyTitle,
                    systemImage: emptyImage,
                    description: emptyDescription
                )
            } else {
                List {
                    ForEach(items.filter(\.isStored)) { article in
                        Button { selectedArticle = article } label: {
                            ArticleRow(article: article)
                        }
                        .buttonStyle(DirectoryRowButtonStyle())
                        .articleListRow(isCurrent: article.isCurrentReading, isSelected: selectedArticle?.id == article.id)
                        .articleActions(for: article, in: modelContext)
                    }
                }
                .oneFeedGroupedListStyle()
            }
        }
        .navigationTitle(destination.title)
        .oneFeedLargeTitle()
        .oneFeedPaperToolbar()
        .background(OneFeedTheme.plaster)
        .searchable(text: $searchText, prompt: "Search articles")
    }

    private var emptyTitle: String {
        if !searchText.isEmpty { return "No matches" }
        return switch destination {
        case .unread: "You're caught up"
        case .folder: "Caught up"
        }
    }

    private var emptyImage: String {
        if !searchText.isEmpty { return "magnifyingglass" }
        return switch destination {
        case .unread: "checkmark.circle"
        case .folder: "checkmark.circle"
        }
    }

    private var emptyDescription: String {
        if !searchText.isEmpty { return "Try a different title or source name." }
        return switch destination {
        case .unread: "New stories from your sources will land here."
        case .folder: "No unread stories in this folder."
        }
    }
}
