import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class CurrentViewModel {
    private var context: ModelContext?
    private let deckService: DailyDeckService
    private let feedService: any FeedRepository
    private let freshRSSService: any FreshRSSSyncing
    private var inFlightRefresh: Task<Void, Never>?
    private var didRunUtilityBackfill = false
    private var hasAppeared = false

    private(set) var currentArticle: Article?
    private(set) var remainingArticles: [Article] = []
    private(set) var displayedArticleID: UUID?
    private(set) var position = 0
    private(set) var totalCount = 0
    private(set) var isRefreshing = false
    let progress = RefreshProgress()
    var presentedError: String?

    var progressLabel: String? {
        guard displayedArticleID != nil, totalCount > 0, position > 0 else { return nil }
        return "\(position) / \(totalCount)"
    }

    var progressAccessibilityLabel: String? {
        guard displayedArticleID != nil, totalCount > 0, position > 0 else { return nil }
        return "Item \(position) of \(totalCount)"
    }

    init() {
        self.deckService = DailyDeckService()
        self.feedService = FeedService()
        self.freshRSSService = FreshRSSSyncService()
    }

    init(
        deckService: DailyDeckService,
        feedService: any FeedRepository,
        freshRSSService: any FreshRSSSyncing
    ) {
        self.deckService = deckService
        self.feedService = feedService
        self.freshRSSService = freshRSSService
    }

    func configure(with context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context
        loadCurrent()
    }

    /// Cheap deck reread when returning to Today. Skips the first appear — configure already loaded.
    func syncVisibleDeck() {
        if !hasAppeared {
            hasAppeared = true
            return
        }
        loadCurrent()
    }

    /// Starts a refresh that outlives Today disappearing, and skips work when feeds are still fresh.
    func startRefreshIfNeeded() {
        if needsRefresh {
            guard inFlightRefresh == nil else { return }
            inFlightRefresh = Task { await self.performRefresh() }
            return
        }
        guard inFlightRefresh == nil, !didRunUtilityBackfill else { return }
        didRunUtilityBackfill = true
        inFlightRefresh = Task(priority: .utility) { await self.backfillThenReload() }
    }

    func loadCurrent() {
        guard let context else { return }
        do {
            // Do not generate here: a first-open generate would freeze today's
            // deck before feeds refresh. Refresh (and background fetch) generate
            // after new items are stored.
            guard let deck = try deckService.todayDeck(in: context) else {
                apply(item: nil, totalCount: 0)
                return
            }
            apply(item: try deckService.currentItem(in: context), totalCount: deck.items.count)
        } catch {
            presentedError = RefreshFailure.message(for: error)
        }
    }

    func transition(to state: ArticleState) {
        guard let context else { return }
        do {
            guard let item = try deckService.currentItem(in: context) else { return }
            if let article = item.article, article.isStored {
                freshRSSService.enqueueMutation(for: article, transition: state, in: context)
            }
            let next = try deckService.advance(item: item, to: state, in: context)
            apply(item: next, totalCount: item.deck?.items.count ?? totalCount)
            Task { await ArticleExtractionService().enrichUpcoming(in: context, from: next) }
        } catch {
            presentedError = RefreshFailure.message(for: error)
        }
    }

    func finish(_ article: Article, as state: ArticleState) {
        guard let context else { return }
        if let item = try? deckService.currentItem(in: context), item.article?.id == article.id {
            transition(to: state)
            return
        }
        ArticleActions.apply(state, to: article, in: context)
        if let deck = try? deckService.todayDeck(in: context),
           let item = deck.items.first(where: { $0.article?.id == article.id }) {
            item.status = state
            try? context.save()
        }
        loadCurrent()
    }

    func refresh() async {
        if let inFlightRefresh {
            await inFlightRefresh.value
        }
        let task = Task { await self.performRefresh() }
        inFlightRefresh = task
        await task.value
    }

    func clearError() { presentedError = nil }

    private var needsRefresh: Bool {
        if isRefreshing { return false }
        let feeds = (try? context?.fetch(FetchDescriptor<Feed>())) ?? []
        let localFeeds = feeds.filter { $0.isEnabled && $0.remoteID == nil }
        if localFeeds.contains(where: { $0.lastFetchedAt == nil }) { return true }
        if let last = BackgroundRefreshCoordinator.lastSuccessfulRefresh,
           Date().timeIntervalSince(last) < BackgroundRefreshCoordinator.staleInterval {
            return false
        }
        if let lastFetched = localFeeds.compactMap(\.lastFetchedAt).max(),
           Date().timeIntervalSince(lastFetched) < BackgroundRefreshCoordinator.staleInterval {
            return false
        }
        return !localFeeds.isEmpty
    }

    private func performRefresh() async {
        guard let context else {
            inFlightRefresh = nil
            return
        }
        isRefreshing = true
        defer {
            progress.finish()
            isRefreshing = false
            inFlightRefresh = nil
        }
        await BackgroundRefreshCoordinator.runExclusive {
            await self.performRefreshWork(in: context)
        }
        loadCurrent()
    }

    private func performRefreshWork(in context: ModelContext) async {
        var refreshError: Error?
        do { try await feedService.refreshAll(in: context, progress: progress) } catch { refreshError = error }
        let provider = SyncProvider.freshRSS.rawValue
        if let account = try? context.fetch(FetchDescriptor<SyncAccount>(predicate: #Predicate { $0.providerRawValue == provider && $0.isEnabled })).first {
            do { try await freshRSSService.sync(account: account, in: context, progress: progress) } catch { refreshError = refreshError ?? error }
        }
        progress.begin(phase: .finishing, total: 1)
        do {
            try await SwiftDataIngest.actor(from: context).finishToday()
            let current = try deckService.currentItem(in: context)
            apply(item: current, totalCount: (try? deckService.todayDeck(in: context))?.items.count ?? 0)
            await ArticleExtractionService().enrichUpcoming(in: context, from: current, extraQueued: 0)
            apply(item: try deckService.currentItem(in: context), totalCount: (try? deckService.todayDeck(in: context))?.items.count ?? totalCount)
            progress.finishItem(newArticles: 0)
        } catch {
            refreshError = refreshError ?? error
            progress.finishItem(newArticles: 0)
        }
        if refreshError == nil { BackgroundRefreshCoordinator.lastSuccessfulRefresh = .now }
        presentedError = refreshError.flatMap(RefreshFailure.message(for:))
    }

    private func backfillThenReload() async {
        guard let context else {
            inFlightRefresh = nil
            return
        }
        await feedService.backfillYouTubeDurations(in: context)
        loadCurrent()
        inFlightRefresh = nil
    }

    private func apply(item: DailyDeckItem?, totalCount: Int) {
        if let article = item?.article, article.isStored {
            currentArticle = article
            displayedArticleID = article.id
        } else {
            currentArticle = nil
            displayedArticleID = nil
        }
        position = item?.position ?? 0
        self.totalCount = totalCount
        if let context {
            remainingArticles = (try? deckService.remainingArticles(in: context)) ?? []
        } else {
            remainingArticles = []
        }
    }
}
