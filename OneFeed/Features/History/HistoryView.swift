import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var history: [Article]

    init() {
        let read = ArticleState.read.rawValue
        let skipped = ArticleState.skipped.rawValue
        _history = Query(ArticleListFetch.rows(
            predicate: #Predicate<Article> { article in
                article.stateRawValue == read || article.stateRawValue == skipped
            },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        ))
    }
    @Query(sort: \NotInterestedEntry.recordedAt, order: .reverse) private var notInterested: [NotInterestedEntry]
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedArticle: Article?
    @State private var appliedSearch = ""
    @State private var queueError: String?
    @State private var storyError: String?
    /// Day groups stay put while the open story changes. Rebuilt off the main thread when search or the list changes.
    @State private var historyDays: [HistoryDay] = []
    @State private var historyReady = false

    private var trimmedQuery: String {
        appliedSearch.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func reloadHistoryDays() async {
        let edge = historyEdge
        let query = trimmedQuery
        let searching = !query.isEmpty
        let snaps = history.compactMap { article -> HistoryStorySnap? in
            guard article.isStored else { return nil }
            return HistoryStorySnap(
                id: article.id,
                completedAt: article.completedAt,
                publishedAt: article.publishedAt,
                title: searching ? article.title : "",
                readingNote: searching ? article.readingNote : "",
                reactionRaw: searching ? article.readingReactionRawValue : "",
                feedTitle: searching ? article.feed?.title : nil,
                url: searching ? article.url : nil,
                author: searching ? article.author : nil,
                contentKind: searching ? article.contentKind : ""
            )
        }
        let plans = await Task.detached(priority: .userInitiated) {
            HistoryViewModel.dayPlans(from: snaps, query: query)
        }.value
        guard !Task.isCancelled, edge == historyEdge else { return }
        let byID = Dictionary(history.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let calendar = Calendar.current
        historyDays = plans.map { plan in
            HistoryDay(
                day: plan.day,
                label: OneFeedDateLabel.historySection(plan.day, calendar: calendar),
                articles: plan.articleIDs.compactMap { byID[$0] }.filter(\.isStored)
            )
        }
        historyReady = true
    }

    /// Search, every story, and the calendar day. Opening a story does not regroup the days.
    /// Coming back the next morning moves “Today” and “Yesterday” forward.
    private var historyEdge: Int {
        _ = scenePhase
        var token = ListIdentity.token(ids: history.lazy.map(\.id))
        token = token &* 31 &+ appliedSearch.hashValue
        token = token &* 31 &+ notInterested.count
        token = token &* 31 &+ Calendar.current.startOfDay(for: .now).hashValue
        return token
    }

    var body: some View {
        OneFeedReadingSplit(article: $selectedArticle) {
            OneFeedSearchHost("Search history", applied: $appliedSearch) {
                historyColumn
            }
        } reader: { article in
            ReaderView(
                article: article,
                onFinish: { state in
                    guard article.isStored else {
                        selectedArticle = nil
                        return true
                    }
                    do {
                        try ArticleActions.apply(state, to: article, in: modelContext)
                    } catch {
                        storyError = UserFacingFailure.message(for: error, fallback: "Couldn’t update that story.")
                        return false
                    }
                    selectedArticle = nil
                    return true
                },
                onClose: { selectedArticle = nil },
                onPutInQueue: {
                    putInQueue(article)
                    selectedArticle = nil
                }
            )
            .onAppear { LibrarySyncService.shared.hasActiveReadingSession = true }
            .onDisappear { LibrarySyncService.shared.hasActiveReadingSession = false }
        }
    }

    private var historyColumn: some View {
        Group {
            if !historyReady && historyDays.isEmpty && notInterested.isEmpty {
                Color.clear
                    .frame(height: 1)
                    .accessibilityHidden(true)
            } else if trimmedQuery.isEmpty && historyDays.isEmpty && notInterested.isEmpty {
                EmptyLibraryState(
                    title: "No history yet",
                    systemImage: "clock",
                    description: "Read and skipped pieces from Today and Queue land here.",
                    actionTitle: "Open Today",
                    action: { NotificationCenter.default.post(name: OneFeedNotify.openToday, object: nil) }
                )
            } else if historyReady && !trimmedQuery.isEmpty && historyDays.isEmpty {
                EmptyLibraryState(
                    title: "No matches",
                    systemImage: "magnifyingglass",
                    description: "Try a title, note, or source name."
                )
            } else {
                List {
                    if trimmedQuery.isEmpty {
                        Section {
                            NavigationLink {
                                NotInterestedView()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Not interested")
                                        .font(.body)
                                        .foregroundStyle(OneFeedTheme.ink)
                                    Text(notInterested.isEmpty
                                         ? "Set aside, grouped by source"
                                         : notInterested.count == 1 ? "1 set aside" : "\(notInterested.count) set aside")
                                        .font(.subheadline)
                                        .foregroundStyle(OneFeedTheme.graphite)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .listRowBackground(OneFeedTheme.paper)
                    }

                    ForEach(historyDays) { group in
                        Section {
                            ForEach(group.articles.filter(\.isStored)) { article in
                                Button { selectedArticle = article } label: {
                                    ArticleRow(article: article, status: article.historyStatus)
                                }
                                .buttonStyle(DirectoryRowButtonStyle())
                                .articleListRow(isSelected: selectedArticle?.id == article.id)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button("Put in Queue", systemImage: "square.stack") {
                                        putInQueue(article)
                                    }
                                    .tint(OneFeedTheme.accent)
                                }
                                .contextMenu {
                                    Button("Put in Queue", systemImage: "square.stack") {
                                        putInQueue(article)
                                    }
                                }
                            }
                        } header: {
                            GallerySectionHeader(text: group.label)
                        }
                    }
                }
                .oneFeedGroupedListStyle()
            }
        }
        .navigationTitle("History")
        .oneFeedInlineTitle()
        .oneFeedPaperToolbar()
        .oneFeedScrollEdge()
        .background(OneFeedTheme.plaster)
        .task(id: historyEdge) {
            await reloadHistoryDays()
        }
        .alert("Couldn’t put that in Queue", isPresented: Binding(
            get: { queueError != nil },
            set: { if !$0 { queueError = nil } }
        )) {
            Button("OK", role: .cancel) { queueError = nil }
        } message: {
            Text(queueError ?? "")
        }
        .alert("Couldn’t update that story", isPresented: Binding(
            get: { storyError != nil },
            set: { if !$0 { storyError = nil } }
        )) {
            Button("OK", role: .cancel) { storyError = nil }
        } message: {
            Text(storyError ?? "")
        }
    }

    private func putInQueue(_ article: Article) {
        guard article.isStored else { return }
        let motion: Animation? = OneFeedMotion.allowsMotion ? OneFeedMotion.list : nil
        var failure: Error?
        withAnimation(motion) {
            do {
                try ArticleQueueService().moveToQueue(article, in: modelContext)
            } catch {
                failure = error
            }
        }
        if let failure {
            queueError = UserFacingFailure.message(for: failure, fallback: "Couldn’t put that in Queue.")
        }
    }
}
