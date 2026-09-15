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
        case .saved: String(localized: "Saved")
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
    @Query(
        filter: #Predicate<Article> { $0.stateRawValue == "saved" || $0.isRemoteStarred }
    ) private var savedQuery: [Article]
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Query private var accounts: [SyncAccount]
    @State private var refresh = BrowseRefresh()
    @State private var showingAddSource = false
    @State private var toolbarDestination: FeedToolbarDestination?

    private var unread: [Article] { FeedFolderGrouping.openArticles(from: openQuery) }
    private var today: [Article] { FeedFolderGrouping.todayArticles(from: openQuery) }
    private var saved: [Article] { FeedFolderGrouping.savedArticles(from: savedQuery) }
    private var summaries: [FolderSummary] { FeedFolderGrouping.folderSummaries(feeds: feeds, articles: openQuery) }
    private var folderSectionTitle: String {
        accounts.contains(where: { $0.provider == .freshRSS && $0.isEnabled })
            ? String(localized: "FreshRSS")
            : String(localized: "Folders")
    }

    var body: some View {
        List {
            Section {
                smartLink(.today, systemImage: "sun.max", count: today.count)
                smartLink(.unread, systemImage: "circle", count: unread.count)
                smartLink(.saved, systemImage: "star", count: saved.count)
            } header: {
                GalleryLabel(text: "Smart Feeds")
            }
            Section {
                if summaries.isEmpty {
                    Text("Folders appear here after you add sources.")
                        .font(OneFeedTheme.sansUI(15, weight: .regular))
                        .foregroundStyle(OneFeedTheme.graphite)
                        .listRowBackground(OneFeedTheme.plaster)
                } else {
                    ForEach(summaries) { summary in
                        NavigationLink {
                            ArticleCollectionView(destination: .folder(summary.folderID))
                        } label: {
                            FeedDirectoryRow(
                                title: summary.name,
                                swatchName: summary.name,
                                count: summary.unreadCount
                            )
                        }
                        .accessibilityIdentifier("folder-\(summary.name)")
                        .accessibilityHint("Opens unread stories in this folder")
                        .listRowBackground(OneFeedTheme.plaster)
                        .listRowSeparatorTint(OneFeedTheme.sand)
                    }
                }
            } header: {
                GalleryLabel(text: folderSectionTitle)
            }
        }
        .        listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(OneFeedTheme.plaster)
        .listRowSeparatorTint(OneFeedTheme.sand)
        .oneFeedScrollEdge()
        .navigationTitle("Feed")
        .oneFeedLargeTitle()
        .navigationSubtitle(refresh.statusText)
        .refreshProgressBanner(refresh.progress)
        .toolbar {
            ToolbarItem(placement: .oneFeedTrailing) {
                OneFeedToolbarRefresh(isRefreshing: refresh.isRefreshing) {
                    Task { await refresh.refresh(in: modelContext) }
                }
            }
            ToolbarItem(placement: .oneFeedTrailing) {
                Button("Add Source", systemImage: "plus") { showingAddSource = true }
            }
            ToolbarItem(placement: .oneFeedTrailing) {
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
            }
        }
        .refreshable { await refresh.refresh(in: modelContext) }
        .task { refresh.adoptLatestFetch(from: feeds) }
        .sheet(isPresented: $showingAddSource) { AddSourceView() }
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
        .listRowBackground(OneFeedTheme.plaster)
        .listRowSeparatorTint(OneFeedTheme.sand)
    }
}

private enum FeedToolbarDestination: Hashable, Identifiable {
    case sources, settings, history
    var id: Self { self }
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
                filter: #Predicate<Article> { $0.stateRawValue == "saved" || $0.isRemoteStarred },
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
                .articleTimelineList()
            }
        }
        .navigationTitle(destination.title)
        .oneFeedInlineTitle()
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
        case .saved: "Nothing saved"
        case .folder: "Caught up"
        }
    }

    private var emptyImage: String {
        switch destination {
        case .today: "sun.max"
        case .unread: "checkmark.circle"
        case .saved: "star"
        case .folder: "checkmark.circle"
        }
    }

    private var emptyDescription: String {
        switch destination {
        case .today: "Stories published today will collect here."
        case .unread: "New stories from your sources will land here."
        case .saved: "Save an article and it will wait here."
        case .folder: "No unread stories in this folder."
        }
    }
}
