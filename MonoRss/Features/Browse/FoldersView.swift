import SwiftData
import SwiftUI

struct FoldersView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var articles: [Article]
    @State private var refresh = BrowseRefresh()
    @State private var selectedArticle: Article?

    private var groups: [FolderArticleGroup] {
        FeedFolderGrouping.folderArticleGroups(from: articles)
    }

    var body: some View {
        Group {
            if groups.isEmpty {
                EmptyLibraryState(
                    title: "No folders yet",
                    systemImage: "folder",
                    description: "Stories group here by FreshRSS folder, or Unfiled if a source has none."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        ForEach(groups) { group in
                            folderSection(group)
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
        }
        .background(OneFeedTheme.grouped.ignoresSafeArea())
        .navigationTitle("Folders")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refresh.refresh(in: modelContext) }
                } label: {
                    if refresh.isRefreshing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
                .accessibilityLabel("Refresh")
            }
        }
        .refreshable { await refresh.refresh(in: modelContext) }
        .navigationDestination(for: FeedFolderID.self) { folderID in
            FolderArticlesView(folderID: folderID)
        }
        .fullScreenCover(item: $selectedArticle) { article in
            ReaderView(article: article) { state in
                selectedArticle = nil
                ArticleActions.apply(state, to: article, in: modelContext)
            }
        }
    }

    private func folderSection(_ group: FolderArticleGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: group.folderID) {
                HStack(spacing: 10) {
                    FolderSwatch(name: group.name)
                    Text(group.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(group.articles.count)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(OneFeedTheme.secondarySurface, in: Capsule())
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, OneFeedTheme.pagePadding)
            .accessibilityIdentifier("folder-\(group.name)")
            .accessibilityHint("Opens all articles in this folder")

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(group.articles.prefix(12)) { article in
                        Button { selectedArticle = article } label: {
                            ArticleCard(article: article, compact: true)
                                .frame(width: 260)
                        }
                        .buttonStyle(.plain)
                        .articleActions(for: article, in: modelContext)
                    }
                }
                .padding(.horizontal, OneFeedTheme.pagePadding)
                .padding(.bottom, 4)
            }
            .scrollClipDisabled()
        }
    }
}

struct FolderArticlesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var articles: [Article]
    let folderID: FeedFolderID
    @State private var selectedArticle: Article?

    private var items: [Article] {
        FeedFolderGrouping.folderArticleGroups(from: articles)
            .first(where: { $0.folderID == folderID })?
            .articles ?? []
    }

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyLibraryState(
                    title: "Caught up",
                    systemImage: "checkmark.circle",
                    description: "No unread stories in this folder."
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
        .navigationTitle(folderID.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedArticle) { article in
            ReaderView(article: article) { state in
                selectedArticle = nil
                ArticleActions.apply(state, to: article, in: modelContext)
            }
        }
    }
}
