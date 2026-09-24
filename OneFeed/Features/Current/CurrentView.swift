import SwiftUI
import SwiftData

struct CurrentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @State private var viewModel = CurrentViewModel()
    @State private var readerArticle: Article?
    @State private var showingAddSource = false
    @State private var showingTodayFilter = false
    @State private var celebrateClear = false
    @State private var keepReadingPaneClear = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stories: [Article] {
        viewModel.remainingArticles.filter(\.isStored)
    }

    /// Every story in the deck. A middle replacement still moves the Mac reader on.
    private var storyEdge: Int {
        ListIdentity.token(ids: stories.lazy.map(\.id))
    }

    var body: some View {
        OneFeedReadingSplit(article: $readerArticle) {
            todayColumn
        } reader: { article in
            ReaderView(article: article, onFinish: { state in
                readerArticle = nil
                guard article.isStored else { return }
                viewModel.finish(article, as: state)
                #if os(macOS)
                keepReadingPaneClear = false
                readerArticle = stories.first
                #endif
            }, onClose: {
                readerArticle = nil
                keepReadingPaneClear = true
            })
            .onAppear { LibrarySyncService.shared.hasActiveReadingSession = true }
            .onDisappear { LibrarySyncService.shared.hasActiveReadingSession = false }
        }
        .readingUndoBanner {
            viewModel.loadCurrent()
            if let open = readerArticle, !viewModel.remainingArticles.contains(where: { $0.id == open.id }) {
                readerArticle = nil
            }
        }
    }

    private var todayColumn: some View {
        Group {
            if stories.isEmpty {
                caughtUp
            } else {
                TodayStoryList(
                    viewModel: viewModel,
                    readerArticleID: readerArticle?.id,
                    open: open
                )
            }
        }
        .background(OneFeedTheme.plaster)
        .overlay {
            ZStack {
                if showsSourceRefreshCover {
                    OneFeedLoadingCover(
                        title: viewModel.progress.primaryText,
                        status: viewModel.progress.coverStatus,
                        canvas: OneFeedTheme.plaster
                    )
                    .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : OneFeedMotion.overlay, value: showsSourceRefreshCover)
        }
        .navigationTitle("Today")
        .oneFeedLargeTitle()
        .oneFeedPaperToolbar()
        .oneFeedScrollEdge()
        .navigationSubtitle(subtitle)
        .refreshProgressBanner(viewModel.progress)
        .toolbar {
            if !feeds.isEmpty {
                ToolbarItem(placement: .oneFeedTrailing) {
                    Button {
                        showingTodayFilter = true
                    } label: {
                        Image(systemName: todayFilterIsNarrowed ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Choose what fills Today")
                    .accessibilityValue(todayFilterIsNarrowed ? "Filtered" : "All sources")
                    .accessibilityIdentifier("today-filter")
                }
            }
            ToolbarItem(placement: .oneFeedTrailing) {
                OneFeedToolbarRefresh(isRefreshing: viewModel.isRefreshing) {
                    Task { await viewModel.refresh() }
                }
            }
            .visibilityPriority(.high)
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
        .onReceive(NotificationCenter.default.publisher(for: OneFeedNotify.storyIndexDidChange)) { _ in
            viewModel.noteStoryIndexChanged()
        }
        .onOpenURL { url in
            guard url.scheme == "onefeed", url.host() == "reader", let article = viewModel.currentArticle else { return }
            open(article)
        }
        .onChange(of: storyEdge) { _, _ in
            #if os(macOS)
            if let current = readerArticle, !stories.contains(where: { $0.id == current.id }) {
                keepReadingPaneClear = false
                readerArticle = stories.first
            } else if readerArticle == nil, !keepReadingPaneClear {
                readerArticle = stories.first
            }
            #endif
        }
        .refreshable { await viewModel.refresh() }
        .sheet(isPresented: $showingAddSource) {
            AddSourceView(onAdded: { Task { await viewModel.refresh() } })
        }
        .sheet(isPresented: $showingTodayFilter) {
            TodayFilterSheet { viewModel.loadCurrent() }
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
        .alert("Couldn’t refresh", isPresented: Binding(get: { viewModel.presentedError != nil }, set: { if !$0 { viewModel.clearError() } })) {
            Button("OK", role: .cancel) { viewModel.clearError() }
        } message: { Text(viewModel.presentedError ?? "") }
    }

    private func open(_ article: Article) {
        keepReadingPaneClear = false
        readerArticle = article
    }

    /// Full-screen cover only while refreshing with no stories yet. Existing stories stay on screen.
    private var showsSourceRefreshCover: Bool {
        viewModel.isRefreshing && stories.isEmpty && !ReaderWebWarmup.skipsOpeningCover
    }

    /// Stays put while a refresh runs. The progress line carries that status, so the title bar does not resize.
    private var subtitle: String {
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
                    OneFeedMark(size: 52)
                    Text(viewModel.progress.remainingText.isEmpty ? "Updating your stories…" : viewModel.progress.remainingText)
                        .font(.system(.title, design: .serif))
                        .foregroundStyle(OneFeedTheme.ink)
                        .multilineTextAlignment(.center)
                } else if celebrateClear {
                    OneFeedMarkBurst(size: 52)
                    Text("You’re all caught up")
                        .font(.system(.title, design: .serif))
                        .foregroundStyle(OneFeedTheme.ink)
                } else if feeds.isEmpty {
                    OneFeedMark(size: 52)
                    Text("Add a source")
                        .font(.system(.title, design: .serif))
                        .foregroundStyle(OneFeedTheme.ink)
                } else if todayHasNoSources {
                    OneFeedMark(size: 52)
                    Text("Nothing set for Today")
                        .font(.system(.title, design: .serif))
                        .foregroundStyle(OneFeedTheme.ink)
                        .multilineTextAlignment(.center)
                } else {
                    OneFeedMark(size: 52)
                    Text("You’re caught up")
                        .font(.system(.title, design: .serif))
                        .foregroundStyle(OneFeedTheme.ink)
                }
            }
        } description: {
            Text(caughtUpDescription)
                .font(.body)
                .foregroundStyle(OneFeedTheme.graphite)
        } actions: {
            Button(caughtUpActionTitle) {
                if feeds.isEmpty {
                    showingAddSource = true
                } else if todayHasNoSources {
                    showingTodayFilter = true
                } else {
                    Task { await viewModel.refresh() }
                }
            }
            .buttonStyle(PrimaryActionStyle())
            .disabled(viewModel.isRefreshing)
        }
        .oneFeedMacEmptyCanvas()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OneFeedTheme.plaster)
        .animation(nil, value: viewModel.progress.completed)
        .sensoryFeedback(.success, trigger: celebrateClear)
    }

    private var todayFilterIsNarrowed: Bool {
        feeds.contains { $0.isEnabled && !$0.includeInToday }
    }

    /// Enabled sources exist, and every one of them is left out of Today.
    private var todayHasNoSources: Bool {
        feeds.contains(where: \.isEnabled) && !feeds.contains { $0.isEnabled && $0.includeInToday }
    }

    private var caughtUpDescription: String {
        if viewModel.isRefreshing { return caughtUpProgressCopy }
        if feeds.isEmpty { return "Follow your favorite publications to find your next read here." }
        if todayHasNoSources { return "Turn a folder or source on. Stories you leave out stay in Feed." }
        return "You’ve finished today’s selection. Refresh to check for new stories."
    }

    private var caughtUpActionTitle: String {
        if viewModel.isRefreshing { return viewModel.progress.countText }
        if feeds.isEmpty { return "Add a source" }
        if todayHasNoSources { return "Choose sources" }
        return "Refresh"
    }

    private var caughtUpProgressCopy: String {
        let detail = viewModel.progress.detailText()
        if detail.isEmpty { return "Fetching your sources. This can take a minute the first time." }
        return detail
    }
}

/// Today’s stories. Kept off the progress line so a refresh tick does not rebuild the deck.
private struct TodayStoryList: View {
    var viewModel: CurrentViewModel
    var readerArticleID: UUID?
    var open: (Article) -> Void
    @Environment(\.modelContext) private var modelContext

    private var stories: [Article] {
        viewModel.remainingArticles.filter(\.isStored)
    }

    var body: some View {
        List {
            if let featured = stories.first {
                Section {
                    Button { open(featured) } label: {
                        FeaturedStory(article: featured, status: viewModel.storyCaptions[featured.id])
                    }
                    .buttonStyle(ArticleCardButtonStyle())
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .articleActions(for: featured, in: modelContext) {
                        viewModel.loadCurrent()
                    }
                } header: {
                    GallerySectionHeader(text: "Up next")
                }
                #if os(iOS)
                .listSectionSeparator(.hidden)
                #endif
            }
            if stories.count > 1 {
                Section {
                    ForEach(Array(stories.dropFirst())) { article in
                        Button { open(article) } label: {
                            ArticleRow(article: article, status: viewModel.storyCaptions[article.id])
                        }
                        .buttonStyle(DirectoryRowButtonStyle())
                        .articleListRow(isCurrent: article.isCurrentReading, isSelected: readerArticleID == article.id)
                        .articleActions(for: article, in: modelContext) {
                            viewModel.loadCurrent()
                        }
                    }
                } header: {
                    GallerySectionHeader(text: "Also today")
                }
                #if os(iOS)
                .listSectionSeparator(.hidden)
                #endif
            }
        }
        .oneFeedGroupedListStyle()
    }
}
