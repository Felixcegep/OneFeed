import SwiftUI
import SwiftData

struct CurrentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = CurrentViewModel()
    @State private var readerArticle: Article?
    @State private var showingSources = false

    private var stories: [Article] {
        viewModel.remainingArticles.filter(\.isStored)
    }

    var body: some View {
        Group {
            if stories.isEmpty {
                caughtUp
            } else {
                List {
                    if let featured = stories.first {
                        Button { readerArticle = featured } label: {
                            FeaturedStory(article: featured)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                        .listRowSeparator(.hidden)
                        .articleActions(for: featured, in: modelContext)
                    }
                    ForEach(Array(stories.dropFirst())) { article in
                        Button { readerArticle = article } label: {
                            ArticleRow(article: article)
                        }
                        .buttonStyle(.plain)
                        .articleListRow()
                        .articleActions(for: article, in: modelContext)
                    }
                }
                .articleTimelineList()
            }
        }
        .navigationTitle("Today")
        .oneFeedLargeTitle()
        .navigationSubtitle(subtitle)
        .refreshProgressBanner(viewModel.progress)
        .task {
            viewModel.configure(with: modelContext)
            if !ProcessInfo.processInfo.arguments.contains("-uiTesting") {
                viewModel.startRefreshIfNeeded()
            }
        }
        .onOpenURL { url in
            guard url.scheme == "onefeed", url.host() == "reader", let article = viewModel.currentArticle else { return }
            readerArticle = article
        }
        .refreshable { await viewModel.refresh() }
        .sheet(isPresented: $showingSources) {
            NavigationStack {
                SourcesView()
            }
        }
        .oneFeedArticleCover(item: $readerArticle) { article in
            ReaderView(article: article, onFinish: { state in
                readerArticle = nil
                guard article.isStored else { return }
                viewModel.finish(article, as: state)
            })
            .onAppear { LibrarySyncService.shared.hasActiveReadingSession = true }
            .onDisappear { LibrarySyncService.shared.hasActiveReadingSession = false }
        }
        .alert("OneFeed", isPresented: Binding(get: { viewModel.presentedError != nil }, set: { if !$0 { viewModel.clearError() } })) {
            Button("OK", role: .cancel) { viewModel.clearError() }
        } message: { Text(viewModel.presentedError ?? "") }
    }

    private var subtitle: String {
        if viewModel.isRefreshing { return viewModel.progress.compactStatus }
        if stories.isEmpty { return "" }
        if viewModel.totalCount > 0 {
            return "\(stories.count) remaining"
        }
        return ""
    }

    private var caughtUp: some View {
        ContentUnavailableView {
            if viewModel.isRefreshing {
                Label {
                    Text(viewModel.progress.remainingText.isEmpty ? "Updating…" : viewModel.progress.remainingText)
                } icon: {
                    ProgressView()
                }
            } else {
                Label("You're caught up.", systemImage: "checkmark.circle")
            }
        } description: {
            Text(viewModel.isRefreshing ? caughtUpProgressCopy : "Tomorrow gets a new stack.")
        } actions: {
            Button(viewModel.isRefreshing ? viewModel.progress.countText : "Refresh") {
                Task { await viewModel.refresh() }
            }
            .disabled(viewModel.isRefreshing)
            Button("Add a source") { showingSources = true }
        }
    }

    private var caughtUpProgressCopy: String {
        let detail = viewModel.progress.detailText()
        if detail.isEmpty { return "Fetching your sources. This can take a minute the first time." }
        return detail
    }
}
