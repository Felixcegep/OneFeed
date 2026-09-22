import SwiftUI
import SwiftData

struct CurrentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @State private var viewModel = CurrentViewModel()
    @State private var readerArticle: Article?
    @State private var showingAddSource = false
    @State private var celebrateClear = false
    @State private var keepReadingPaneClear = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stories: [Article] {
        viewModel.remainingArticles.filter(\.isStored)
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
    }

    private var todayColumn: some View {
        Group {
            if stories.isEmpty {
                caughtUp
            } else {
                List {
                    if let featured = stories.first {
                        Section {
                            Button { open(featured) } label: {
                                FeaturedStory(article: featured)
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
                                    ArticleRow(article: article)
                                }
                                .buttonStyle(DirectoryRowButtonStyle())
                                .articleListRow(isCurrent: article.isCurrentReading, isSelected: readerArticle?.id == article.id)
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
        .onOpenURL { url in
            guard url.scheme == "onefeed", url.host() == "reader", let article = viewModel.currentArticle else { return }
            open(article)
        }
        .onChange(of: stories.map(\.id)) { _, ids in
            #if os(macOS)
            if let current = readerArticle, !ids.contains(current.id) {
                keepReadingPaneClear = false
                readerArticle = stories.first
            } else if readerArticle == nil, !keepReadingPaneClear {
                readerArticle = stories.first
            }
            #endif
        }
        .refreshable { await viewModel.refresh() }
        .sheet(isPresented: $showingAddSource, onDismiss: {
            if !feeds.isEmpty { Task { await viewModel.refresh() } }
        }) { AddSourceView() }
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

    private func open(_ article: Article) {
        keepReadingPaneClear = false
        readerArticle = article
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
                } else {
                    OneFeedMark(size: 52)
                    Text("You’re caught up")
                        .font(.system(.title, design: .serif))
                        .foregroundStyle(OneFeedTheme.ink)
                }
            }
        } description: {
            Text(viewModel.isRefreshing ? caughtUpProgressCopy : feeds.isEmpty ? "Follow your favorite publications to find your next read here." : "You’ve finished today’s selection. Refresh to check for new stories.")
                .font(.body)
                .foregroundStyle(OneFeedTheme.graphite)
        } actions: {
            Button(viewModel.isRefreshing ? viewModel.progress.countText : feeds.isEmpty ? "Add a source" : "Refresh") {
                if feeds.isEmpty {
                    showingAddSource = true
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

    private var caughtUpProgressCopy: String {
        let detail = viewModel.progress.detailText()
        if detail.isEmpty { return "Fetching your sources. This can take a minute the first time." }
        return detail
    }
}
