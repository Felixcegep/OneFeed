import SwiftData
import SwiftUI

struct RecentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Article.publishedAt, order: .reverse) private var articles: [Article]
    @State private var refresh = BrowseRefresh()
    @State private var selectedArticle: Article?
    @State private var search = ""

    private var visible: [Article] {
        let open = FeedFolderGrouping.openArticles(from: articles)
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return open }
        return open.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || ($0.feed?.title.localizedCaseInsensitiveContains(query) ?? false)
                || ($0.summary?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        Group {
            if visible.isEmpty {
                EmptyLibraryState(
                    title: search.isEmpty ? "Nothing new" : "No matches",
                    systemImage: search.isEmpty ? "sparkles" : "magnifyingglass",
                    description: search.isEmpty
                        ? "New stories from your sources will land here."
                        : "Try a source name or a different phrase."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(visible) { article in
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
        .navigationTitle("Recent")
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search articles")
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
        .fullScreenCover(item: $selectedArticle) { article in
            ReaderView(article: article) { state in
                selectedArticle = nil
                ArticleActions.apply(state, to: article, in: modelContext)
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
}
