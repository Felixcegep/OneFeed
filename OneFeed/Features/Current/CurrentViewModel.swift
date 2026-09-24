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
    private var inFlightIsFullRefresh = false
    private var didRunUtilityBackfill = false
    private var hasAppeared = false

    private(set) var currentArticle: Article?
    private(set) var remainingArticles: [Article] = []
    private(set) var displayedArticleID: UUID?
    private(set) var position = 0
    private(set) var totalCount = 0
    private(set) var isRefreshing = false
    private var captionStamp = Int.min
    private var captionGeneration = 0
    private var captionTask: Task<Void, Never>?
    private var cachedCaptions: [UUID: String] = [:]
    private(set) var storyCaptions: [UUID: String] = [:]
    private(set) var featuredExcerpt: String?
    private(set) var featuredExcerptID: UUID?
    let progress = RefreshProgress()
    var presentedError: String?
    var storyError: String?

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
            inFlightIsFullRefresh = true
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

    func transition(to state: ArticleState) -> Bool {
        guard let context else { return false }
        do {
            guard let item = try deckService.currentItem(in: context) else { return true }
            let article = item.resolvedArticleID().flatMap { DailyDeckService.lightweightArticle(id: $0, in: context) }
            if let article {
                if state == .skipped {
                    ReadingUndo.begin(article, in: context)
                }
                freshRSSService.enqueueMutation(for: article, transition: state, in: context)
            }
            let next = try deckService.advance(item: item, to: state, in: context)
            if state == .skipped, let article {
                ReadingUndo.commit(article, in: context)
            }
            apply(item: next, totalCount: item.deck?.items.count ?? totalCount)
            Task { await BackgroundRefreshCoordinator.enrichAfterRefresh(in: context, from: next, extraQueued: 2) }
            return true
        } catch {
            storyError = UserFacingFailure.message(for: error, fallback: "Couldn’t update that story.")
            return false
        }
    }

    @discardableResult
    func finish(_ article: Article, as state: ArticleState) -> Bool {
        guard let context else { return false }
        if let item = try? deckService.currentItem(in: context), item.resolvedArticleID() == article.id {
            return transition(to: state)
        }
        do {
            try ArticleActions.apply(state, to: article, in: context)
            if let deck = try deckService.todayDeck(in: context),
               let item = deck.items.first(where: { $0.resolvedArticleID() == article.id }) {
                item.status = state
                try context.save()
            }
        } catch {
            storyError = UserFacingFailure.message(for: error, fallback: "Couldn’t update that story.")
            return false
        }
        loadCurrent()
        return true
    }

    func refresh() async {
        if let existing = inFlightRefresh {
            let joiningFullRefresh = inFlightIsFullRefresh
            await existing.value
            if joiningFullRefresh { return }
        }
        guard inFlightRefresh == nil else {
            await refresh()
            return
        }
        inFlightIsFullRefresh = true
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
            inFlightIsFullRefresh = false
        }
        await BackgroundRefreshCoordinator.runExclusive {
            await self.performRefreshWork(in: context)
        }
        loadCurrent()
        Task { await BackgroundRefreshCoordinator.enrichAfterRefresh(in: context) }
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
        if let context, let id = item?.resolvedArticleID(),
           let article = DailyDeckService.lightweightArticle(id: id, in: context) {
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
            scheduleCaptions()
        } else {
            remainingArticles = []
            scheduleCaptions()
        }
    }

    /// The story index can land after the deck is already on screen. Reload the captions without rebuilding the deck.
    func noteStoryIndexChanged() {
        captionGeneration &+= 1
        scheduleCaptions()
    }

    /// Same deck within the hour reuses captions. A finished story, a new hour, or a new story index loads them again.
    /// The lookup itself runs off the main actor, so Today can draw the deck first.
    private func scheduleCaptions() {
        let articles = remainingArticles
        guard !articles.isEmpty, let context else {
            captionTask?.cancel()
            captionStamp = Int.min
            cachedCaptions = [:]
            storyCaptions = [:]
            featuredExcerpt = nil
            featuredExcerptID = nil
            return
        }
        let stamp = Self.captionStamp(for: articles, generation: captionGeneration)
        if stamp == captionStamp { return }
        let subjects = articles.map {
            StoryCaptionSubject(id: $0.id, identityKey: ArticleIdentity.identityKey(for: $0))
        }
        let featured = articles.first
        let excerptSample = CardExcerptSample(
            aiSummary: ContentClassifier.cardExcerptSample(featured?.aiSummary),
            summary: ContentClassifier.cardExcerptSample(featured?.summary)
        )
        if featured?.id != featuredExcerptID {
            featuredExcerpt = nil
            featuredExcerptID = nil
        }
        let container = context.container
        let generation = captionGeneration
        captionTask?.cancel()
        captionTask = Task {
            async let built = StoryGrouping.captions(for: subjects, in: container)
            let excerpt = await Task.detached(priority: .userInitiated) {
                ContentClassifier.cardExcerpt(aiSummary: excerptSample.aiSummary, summary: excerptSample.summary)
            }.value
            let captions = await built
            guard !Task.isCancelled, generation == captionGeneration else { return }
            captionStamp = stamp
            cachedCaptions = captions
            storyCaptions = captions
            featuredExcerpt = excerpt
            featuredExcerptID = featured?.id
        }
    }

    private static func captionStamp(for articles: [Article], generation: Int, now: Date = .now) -> Int {
        var stamp = articles.count
        stamp ^= generation
        stamp ^= Int(now.timeIntervalSince1970 / 3600)
        for article in articles {
            stamp ^= article.id.hashValue
            stamp ^= article.stateRawValue.hashValue
        }
        return stamp
    }
}
