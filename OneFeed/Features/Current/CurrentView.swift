import SwiftUI
import SwiftData

struct CurrentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = CurrentViewModel()
    @State private var readerArticle: Article?
    @State private var showingSources = false
    @State private var celebrateClear = false

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
                        .buttonStyle(DirectoryRowButtonStyle())
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(OneFeedTheme.plaster)
                        .listRowSeparatorTint(OneFeedTheme.sand)
                        .articleActions(for: featured, in: modelContext)
                    }
                    ForEach(Array(stories.dropFirst())) { article in
                        Button { readerArticle = article } label: {
                            ArticleRow(article: article)
                        }
                        .buttonStyle(DirectoryRowButtonStyle())
                        .articleListRow()
                        .articleActions(for: article, in: modelContext)
                    }
                }
                .articleTimelineList()
                .animation(viewModel.isRefreshing ? nil : OneFeedMotion.overlay, value: stories.count)
            }
        }
        .animation(viewModel.isRefreshing ? nil : OneFeedMotion.page, value: stories.isEmpty)
        .background(OneFeedTheme.plaster)
        .navigationTitle("Today")
        .oneFeedLargeTitle()
        .navigationSubtitle(subtitle)
        .refreshProgressBanner(viewModel.progress)
        .toolbar {
            ToolbarItem(placement: .oneFeedTrailing) {
                OneFeedToolbarRefresh(isRefreshing: viewModel.isRefreshing) {
                    Task { await viewModel.refresh() }
                }
            }
            ToolbarItem(placement: .oneFeedTrailing) {
                Button("Add Source", systemImage: "plus") { showingSources = true }
            }
        }
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
        .onChange(of: stories.count) { oldCount, newCount in
            if oldCount > 0, newCount == 0, !viewModel.isRefreshing {
                celebrateClear = true
            }
        }
        .onChange(of: celebrateClear) { _, celebrating in
            guard celebrating else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                celebrateClear = false
            }
        }
        .alert("OneFeed", isPresented: Binding(get: { viewModel.presentedError != nil }, set: { if !$0 { viewModel.clearError() } })) {
            Button("OK", role: .cancel) { viewModel.clearError() }
        } message: { Text(viewModel.presentedError ?? "") }
    }

    private var subtitle: String {
        if viewModel.isRefreshing { return viewModel.progress.primaryText }
        if stories.isEmpty { return "" }
        if viewModel.totalCount > 0 {
            return "\(stories.count) remaining"
        }
        return ""
    }

    private var caughtUp: some View {
        ContentUnavailableView {
            VStack(spacing: 20) {
                if viewModel.isRefreshing {
                    OneFeedMarkPulse(isActive: true, size: 52)
                    Text(viewModel.progress.remainingText.isEmpty ? "Hanging the room…" : viewModel.progress.remainingText)
                        .font(OneFeedTheme.serifDisplay(32))
                        .foregroundStyle(OneFeedTheme.ink)
                        .multilineTextAlignment(.center)
                } else if celebrateClear {
                    OneFeedMarkBurst(size: 52)
                    Text("The room is still.")
                        .font(OneFeedTheme.serifDisplay(32))
                        .foregroundStyle(OneFeedTheme.ink)
                } else {
                    OneFeedMark(size: 52)
                    Text("The room is still.")
                        .font(OneFeedTheme.serifDisplay(32))
                        .foregroundStyle(OneFeedTheme.ink)
                }
            }
        } description: {
            Text(viewModel.isRefreshing ? caughtUpProgressCopy : "Tomorrow, a new hanging.")
                .font(OneFeedTheme.sansUI(16, weight: .regular))
                .foregroundStyle(OneFeedTheme.graphite)
        } actions: {
            Button(viewModel.isRefreshing ? viewModel.progress.countText : "Refresh") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(PrimaryActionStyle())
            .disabled(viewModel.isRefreshing)
            Button("Add a source") { showingSources = true }
                .font(OneFeedTheme.sansUI(15, weight: .regular))
                .foregroundStyle(OneFeedTheme.graphite)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OneFeedTheme.plaster)
        .sensoryFeedback(.success, trigger: celebrateClear)
    }

    private var caughtUpProgressCopy: String {
        let detail = viewModel.progress.detailText()
        if detail.isEmpty { return "Fetching your sources. This can take a minute the first time." }
        return detail
    }
}
