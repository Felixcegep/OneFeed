import SwiftUI
import SwiftData

struct CurrentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @State private var viewModel = CurrentViewModel()
    @State private var readerArticle: Article?
    @State private var showingSources = false
    @State private var celebrateClear = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        Section {
                            Button { readerArticle = featured } label: {
                                FeaturedStory(article: featured)
                            }
                            .buttonStyle(ArticleCardButtonStyle())
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .articleActions(for: featured, in: modelContext)
                        } header: {
                            GallerySectionHeader(text: "Now")
                        }
                    }
                    if stories.count > 1 {
                        Section {
                            ForEach(Array(stories.dropFirst())) { article in
                                Button { readerArticle = article } label: {
                                    ArticleRow(article: article)
                                }
                                .buttonStyle(DirectoryRowButtonStyle())
                                .articleListRow()
                                .articleActions(for: article, in: modelContext)
                            }
                        } header: {
                            GallerySectionHeader(text: "Also today")
                        }
                    }
                }
                .oneFeedGroupedListStyle()
            }
        }
        .background(OneFeedTheme.plaster)
        .overlay {
            if showsSourceRefreshCover {
                OneFeedLoadingCover(
                    title: viewModel.progress.primaryText,
                    status: viewModel.progress.coverStatus,
                    canvas: OneFeedTheme.plaster
                )
            }
        }
        .animation(reduceMotion ? nil : OneFeedMotion.overlay, value: showsSourceRefreshCover)
        .navigationTitle("Today")
        .oneFeedLargeTitle()
        .oneFeedPaperToolbar()
        .oneFeedScrollEdge()
        .navigationSubtitle(subtitle)
        .refreshProgressBanner(viewModel.progress)
        .toolbar {
            ToolbarItemGroup(placement: .oneFeedTrailing) {
                OneFeedToolbarRefresh(isRefreshing: viewModel.isRefreshing) {
                    Task { await viewModel.refresh() }
                }
                Button("Add Source", systemImage: "plus") { showingSources = true }
            }
        }
        .task {
            viewModel.configure(with: modelContext)
            let process = ProcessInfo.processInfo
            let hostedByTests = process.arguments.contains("-uiTesting")
                || process.environment["XCTestConfigurationFilePath"] != nil
                || process.environment["XCTestBundlePath"] != nil
            if !hostedByTests {
                viewModel.startRefreshIfNeeded()
            }
        }
        .onAppear { viewModel.syncVisibleDeck() }
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

    private var showsSourceRefreshCover: Bool {
        viewModel.isRefreshing && !ReaderWebWarmup.skipsOpeningCover
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
                        .font(.system(.title, design: .serif))
                        .foregroundStyle(OneFeedTheme.ink)
                        .multilineTextAlignment(.center)
                } else if celebrateClear {
                    OneFeedMarkBurst(size: 52)
                    Text("The room is still.")
                        .font(.system(.title, design: .serif))
                        .foregroundStyle(OneFeedTheme.ink)
                } else if feeds.isEmpty {
                    OneFeedMark(size: 52)
                    Text("Add a source")
                        .font(.system(.title, design: .serif))
                        .foregroundStyle(OneFeedTheme.ink)
                } else {
                    OneFeedMark(size: 52)
                    Text("You’re caught up")
                        .font(.system(.title, design: .serif))
                        .foregroundStyle(OneFeedTheme.ink)
                }
            }
        } description: {
            Text(viewModel.isRefreshing ? caughtUpProgressCopy : feeds.isEmpty ? "Today fills after you subscribe." : "Tomorrow, a new hanging.")
                .font(.body)
                .foregroundStyle(OneFeedTheme.graphite)
        } actions: {
            Button(viewModel.isRefreshing ? viewModel.progress.countText : feeds.isEmpty ? "Add a source" : "Refresh") {
                if feeds.isEmpty {
                    showingSources = true
                } else {
                    Task { await viewModel.refresh() }
                }
            }
            .buttonStyle(PrimaryActionStyle())
            .disabled(viewModel.isRefreshing)
            if !feeds.isEmpty {
                Button("Add a source") { showingSources = true }
                    .font(.subheadline)
                    .foregroundStyle(OneFeedTheme.graphite)
                    .frame(minHeight: 44)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OneFeedTheme.plaster)
        .animation(nil, value: viewModel.progress.completed)
        .sensoryFeedback(.success, trigger: celebrateClear)
    }

    private var caughtUpProgressCopy: String {
        let detail = viewModel.progress.detailText()
        if detail.isEmpty { return "Fetching your sources. This can take a minute the first time." }
        return detail
    }
}
