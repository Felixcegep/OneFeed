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
    @State private var todayFilterError: String?
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
                guard article.isStored else {
                    readerArticle = nil
                    return true
                }
                guard viewModel.finish(article, as: state) else { return false }
                readerArticle = nil
                #if os(macOS)
                keepReadingPaneClear = false
                readerArticle = stories.first
                #endif
                return true
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
        .modifier(TodayRefreshChrome(
            viewModel: viewModel,
            hasStories: !stories.isEmpty,
            hasFeeds: !feeds.isEmpty,
            reduceMotion: reduceMotion
        ))
        .navigationTitle("Today")
        .oneFeedLargeTitle()
        .oneFeedPaperToolbar()
        .oneFeedScrollEdge()
        .navigationSubtitle(subtitle)
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
            TodayFilterSheet(onUpdated: { viewModel.loadCurrent() }, onFailed: { todayFilterError = $0 })
        }
        .onChange(of: stories.count) { oldCount, newCount in
            if oldCount > 0, newCount == 0, !viewModel.isRefreshing {
                celebrateClear = true
            }
        }
        .task(id: celebrateClear) {
            guard celebrateClear else { return }
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            celebrateClear = false
        }
        .alert("Couldn’t update Today", isPresented: Binding(
            get: { todayFilterError != nil },
            set: { if !$0 { todayFilterError = nil } }
        )) {
            Button("OK", role: .cancel) { todayFilterError = nil }
        } message: { Text(todayFilterError ?? "") }
        .alert("Couldn’t refresh", isPresented: Binding(get: { viewModel.presentedError != nil }, set: { if !$0 { viewModel.clearError() } })) {
            Button("OK", role: .cancel) { viewModel.clearError() }
        } message: { Text(viewModel.presentedError ?? "") }
        .alert("Couldn’t update that story", isPresented: Binding(
            get: { viewModel.storyError != nil },
            set: { if !$0 { viewModel.storyError = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.storyError = nil }
        } message: { Text(viewModel.storyError ?? "") }
    }

    private func open(_ article: Article) {
        keepReadingPaneClear = false
        readerArticle = article
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
                if emptyCopy == .celebrate {
                    OneFeedMarkBurst(size: 52)
                } else {
                    OneFeedMark(size: 52)
                }
                Text(emptyCopy.title)
                    .font(.system(.title, design: .serif))
                    .foregroundStyle(OneFeedTheme.ink)
                    .multilineTextAlignment(.center)
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
        .sensoryFeedback(.success, trigger: celebrateClear) { _, celebrating in
            celebrating
        }
    }

    private var todayFilterIsNarrowed: Bool {
        feeds.contains { $0.isEnabled && !$0.includeInToday }
    }

    /// Enabled sources exist, and every one of them is left out of Today.
    private var todayHasNoSources: Bool {
        feeds.contains(where: \.isEnabled) && !feeds.contains { $0.isEnabled && $0.includeInToday }
    }

    private var emptyCopy: TodayEmptyCopy {
        TodayEmptyCopy.choose(
            isRefreshing: viewModel.isRefreshing,
            hasFeeds: !feeds.isEmpty,
            todayHasNoSources: todayHasNoSources,
            finishedSelection: viewModel.totalCount > 0,
            celebrate: celebrateClear
        )
    }

    private var caughtUpDescription: String {
        emptyCopy.detail
    }

    private var caughtUpActionTitle: String {
        if feeds.isEmpty { return "Add a source" }
        if todayHasNoSources { return "Choose sources" }
        return "Refresh"
    }
}

/// Progress ticks stay on this chrome. Today’s deck does not read the progress line, so a refresh does not rebuild the stories.
private struct TodayRefreshChrome: ViewModifier {
    var viewModel: CurrentViewModel
    var hasStories: Bool
    var hasFeeds: Bool
    var reduceMotion: Bool

    private var showsCover: Bool {
        TodayRefreshCover.isShown(
            isRefreshing: viewModel.isRefreshing,
            hasStories: hasStories,
            hasFeeds: hasFeeds,
            skipsOpeningCover: ReaderWebWarmup.skipsOpeningCover
        )
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    if showsCover {
                        OneFeedLoadingCover(
                            title: viewModel.progress.primaryText,
                            status: viewModel.progress.coverStatus,
                            canvas: OneFeedTheme.plaster
                        )
                        .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : OneFeedMotion.overlay, value: showsCover)
            }
            .refreshProgressBanner(viewModel.progress)
            .toolbar {
                ToolbarItem(placement: .oneFeedTrailing) {
                    OneFeedToolbarRefresh(isRefreshing: viewModel.isRefreshing) {
                        Task { await viewModel.refresh() }
                    }
                }
                .visibilityPriority(.high)
            }
    }
}

/// The full-screen refresh cover is for the first load, before any source exists.
/// What an empty Today says. A finished selection stays put while a refresh runs.
enum TodayEmptyCopy: Equatable {
    case updating
    case celebrate
    case addSource
    case noSources
    case caughtUp

    static func choose(
        isRefreshing: Bool,
        hasFeeds: Bool,
        todayHasNoSources: Bool,
        finishedSelection: Bool,
        celebrate: Bool
    ) -> TodayEmptyCopy {
        if isRefreshing && !hasFeeds { return .updating }
        if celebrate { return .celebrate }
        if !hasFeeds { return .addSource }
        if todayHasNoSources { return .noSources }
        if isRefreshing && !finishedSelection { return .updating }
        return .caughtUp
    }

    var title: String {
        switch self {
        case .updating: "Updating your stories…"
        case .celebrate: "You’re all caught up"
        case .addSource: "Add a source"
        case .noSources: "Nothing set for Today"
        case .caughtUp: "You’re caught up"
        }
    }

    var detail: String {
        switch self {
        case .updating: "Checking your sources for new stories."
        case .celebrate, .caughtUp: "You’ve finished today’s selection. Refresh to check for new stories."
        case .addSource: "Follow your favorite publications to find your next read here."
        case .noSources: "Turn a folder or source on. Stories you leave out stay in Feed."
        }
    }
}

enum TodayRefreshCover {
    static func isShown(isRefreshing: Bool, hasStories: Bool, hasFeeds: Bool, skipsOpeningCover: Bool) -> Bool {
        isRefreshing && !hasStories && !hasFeeds && !skipsOpeningCover
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
                        FeaturedStory(
                            article: featured,
                            status: viewModel.storyCaptions[featured.id],
                            preparedExcerpt: viewModel.featuredExcerptID == featured.id ? viewModel.featuredExcerpt : nil,
                            usesPreparedExcerpt: true
                        )
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
