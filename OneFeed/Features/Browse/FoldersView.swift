import SwiftData
import SwiftUI

enum FeedBrowseDestination: Hashable {
    case today
    case unread
    case saved
    case folder(FeedFolderID)

    var title: String {
        switch self {
        case .today: String(localized: "Today")
        case .unread: String(localized: "All Unread")
        case .saved: String(localized: "Queue")
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
    @Query private var accounts: [SyncAccount]
    @State private var refresh = BrowseRefresh()
    @State private var showingAddSource = false
    @State private var toolbarDestination: FeedToolbarDestination?
    @State private var pickingFolder: FolderIconTarget?
    @State private var iconTick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var folderSectionTitle: String {
        accounts.contains(where: { $0.provider == .freshRSS && $0.isEnabled })
            ? String(localized: "FreshRSS")
            : String(localized: "Folders")
    }

    private var showsSourceRefreshCover: Bool {
        refresh.isRefreshing && !ReaderWebWarmup.skipsOpeningCover
    }

    var body: some View {
        let directory = FeedRootDirectory(feeds: feeds, articles: openQuery)
        let _ = iconTick
        List {
            Section {
                smartLink(.unread, systemImage: "tray", count: directory.unreadCount)
                smartLink(.today, systemImage: "sun.max", count: directory.todayCount)
            } header: {
                GallerySectionHeader(text: "Smart Feeds")
            }
            Section {
                if directory.summaries.isEmpty {
                    Text("Folders appear here after you add sources.")
                        .font(OneFeedTheme.sansUI(15, weight: .regular))
                        .foregroundStyle(OneFeedTheme.graphite)
                        .oneFeedDirectoryRow()
                } else {
                    ForEach(directory.summaries) { summary in
                        folderRow(summary)
                    }
                }
            } header: {
                GallerySectionHeader(text: folderSectionTitle)
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
            ToolbarItemGroup(placement: .oneFeedTrailing) {
                OneFeedToolbarRefresh(isRefreshing: refresh.isRefreshing) {
                    Task { await refresh.refresh(in: modelContext) }
                }
                Button("Add Source", systemImage: "plus") { showingAddSource = true }
                Menu {
                    Button("Sources", systemImage: "dot.radiowaves.left.and.right") {
                        toolbarDestination = .sources
                    }
                    Button("History", systemImage: "clock") {
                        toolbarDestination = .history
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
            case .history: HistoryView()
            }
        }
        .refreshable { await refresh.refresh(in: modelContext) }
        .task { refresh.adoptLatestFetch(from: feeds) }
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

    private func smartLink(_ destination: FeedBrowseDestination, systemImage: String, count: Int) -> some View {
        NavigationLink {
            ArticleCollectionView(destination: destination)
        } label: {
            FeedDirectoryRow(title: destination.title, systemImage: systemImage, count: count)
        }
        .oneFeedDirectoryRow()
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
                    title: summary.name,
                    count: summary.unreadCount
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
    case sources, history
    var id: Self { self }
}

private struct FeedRootDirectory {
    let unreadCount: Int
    let todayCount: Int
    let summaries: [FolderSummary]

    init(feeds: [Feed], articles: [Article]) {
        let open = FeedFolderGrouping.openArticles(from: articles)
        unreadCount = open.count
        todayCount = open.reduce(into: 0) { count, article in
            if Calendar.current.isDateInToday(article.publishedAt) { count += 1 }
        }
        summaries = FeedFolderGrouping.folderSummaries(feeds: feeds, openArticles: open)
    }
}

struct ArticleCollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var articles: [Article]
    let destination: FeedBrowseDestination
    @State private var selectedArticle: Article?

    init(destination: FeedBrowseDestination) {
        self.destination = destination
        switch destination {
        case .saved:
            _articles = Query(
                filter: #Predicate<Article> { $0.stateRawValue == "saved" },
                sort: \Article.completedAt,
                order: .reverse
            )
        default:
            _articles = Query(
                filter: #Predicate<Article> { $0.stateRawValue == "queued" || $0.stateRawValue == "current" },
                sort: \Article.publishedAt,
                order: .reverse
            )
        }
    }

    private var items: [Article] {
        switch destination {
        case .today: FeedFolderGrouping.todayArticles(from: articles)
        case .unread: FeedFolderGrouping.openArticles(from: articles)
        case .saved: FeedFolderGrouping.savedArticles(from: articles)
        case .folder(let folderID):
            FeedFolderGrouping.folderArticleGroups(from: articles)
                .first(where: { $0.folderID == folderID })?
                .articles ?? []
        }
    }

    var body: some View {
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
                        .articleListRow()
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
        .oneFeedArticleCover(item: $selectedArticle) { article in
            ReaderView(article: article) { state in
                selectedArticle = nil
                guard article.isStored else { return }
                ArticleActions.apply(state, to: article, in: modelContext)
            }
            .onAppear { LibrarySyncService.shared.hasActiveReadingSession = true }
            .onDisappear { LibrarySyncService.shared.hasActiveReadingSession = false }
        }
    }

    private var emptyTitle: String {
        switch destination {
        case .today: "Nothing today"
        case .unread: "You're caught up"
        case .saved: "Nothing in Queue"
        case .folder: "Caught up"
        }
    }

    private var emptyImage: String {
        switch destination {
        case .today: "sun.max"
        case .unread: "checkmark.circle"
        case .saved: "square.stack"
        case .folder: "checkmark.circle"
        }
    }

    private var emptyDescription: String {
        switch destination {
        case .today: "Stories published today will collect here."
        case .unread: "New stories from your sources will land here."
        case .saved: "Add a link or file, or pick a story from Feed."
        case .folder: "No unread stories in this folder."
        }
    }
}
