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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var articles: [Article]
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Query private var accounts: [SyncAccount]
    @State private var refresh = BrowseRefresh()
    @State private var smartFeedsExpanded = true
    @State private var foldersExpanded = true

    private var unread: [Article] { FeedFolderGrouping.openArticles(from: articles) }
    private var today: [Article] { FeedFolderGrouping.todayArticles(from: articles) }
    private var saved: [Article] { FeedFolderGrouping.savedArticles(from: articles) }
    private var summaries: [FolderSummary] { FeedFolderGrouping.folderSummaries(feeds: feeds, articles: articles) }
    private var folderSectionTitle: String {
        accounts.contains(where: { $0.provider == .freshRSS && $0.isEnabled })
            ? String(localized: "FreshRSS")
            : String(localized: "Folders")
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                directorySection("Smart Feeds", expanded: $smartFeedsExpanded) {
                    directoryLink(.today, systemImage: "sun.max", count: today.count)
                    directoryLink(.unread, systemImage: "circle", count: unread.count)
                    directoryLink(.saved, systemImage: "bookmark", count: saved.count)
                }
                directorySection(folderSectionTitle, expanded: $foldersExpanded) {
                    if summaries.isEmpty {
                        Text("Folders appear here after you add sources.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                    } else {
                        ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                            NavigationLink(value: FeedBrowseDestination.folder(summary.folderID)) {
                                FeedDirectoryRow(
                                    title: summary.name,
                                    swatchName: summary.name,
                                    count: summary.unreadCount
                                )
                            }
                            .buttonStyle(DirectoryRowButtonStyle())
                            .accessibilityIdentifier("folder-\(summary.name)")
                            .accessibilityHint("Opens unread stories in this folder")
                            if index < summaries.count - 1 { rowDivider }
                        }
                    }
                }
            }
            .padding(.horizontal, OneFeedTheme.pagePadding)
            .padding(.vertical, 12)
        }
        .background(OneFeedTheme.grouped.ignoresSafeArea())
        .navigationTitle("Feeds")
        .navigationSubtitle(refresh.statusText)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refresh.refresh(in: modelContext) }
                } label: {
                    if refresh.isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(refresh.isRefreshing)
                .accessibilityLabel("Refresh")
            }
        }
        .refreshable { await refresh.refresh(in: modelContext) }
        .task { refresh.adoptLatestFetch(from: feeds) }
        .navigationDestination(for: FeedBrowseDestination.self) { destination in
            ArticleCollectionView(destination: destination)
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

    private func directorySection<Content: View>(
        _ title: String,
        expanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    expanded.wrappedValue.toggle()
                }
            } label: {
                OneFeedSectionLabel(title: title, expanded: expanded.wrappedValue)
            }
            .buttonStyle(.plain)
            .accessibilityHint(expanded.wrappedValue ? "Collapses this section" : "Expands this section")

            if expanded.wrappedValue {
                OneFeedGroupCard { content() }
            }
        }
    }

    @ViewBuilder
    private func directoryLink(_ destination: FeedBrowseDestination, systemImage: String, count: Int) -> some View {
        NavigationLink(value: destination) {
            FeedDirectoryRow(title: destination.title, systemImage: systemImage, count: count)
        }
        .buttonStyle(DirectoryRowButtonStyle())
        if destination != .saved { rowDivider }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 1)
            .padding(.leading, 60)
    }
}

struct ArticleCollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var articles: [Article]
    let destination: FeedBrowseDestination
    @State private var selectedArticle: Article?

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
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(items) { article in
                            Button { selectedArticle = article } label: {
                                ArticleCard(article: article)
                            }
                            .buttonStyle(.plain)
                            .articleActions(for: article, in: modelContext)
                        }
                    }
                    .padding(.horizontal, OneFeedTheme.pagePadding)
                    .padding(.vertical, 12)
                }
            }
        }
        .background(OneFeedTheme.grouped.ignoresSafeArea())
        .navigationTitle(destination.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedArticle) { article in
            ReaderView(article: article) { state in
                selectedArticle = nil
                ArticleActions.apply(state, to: article, in: modelContext)
            }
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
        case .saved: "bookmark"
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
