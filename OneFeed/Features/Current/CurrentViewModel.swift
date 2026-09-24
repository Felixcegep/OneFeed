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
    private(set) var spokenCaptions: [UUID: String] = [:]
    private(set) var featuredExcerpt: String?
    private(set) var featuredExcerptID: UUID?
    /// Plain previews for stories that are about to become the featured card.
    private var prefetchedExcerpts: [UUID: PrefetchedExcerpt] = [:]
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

    /// Starts a refresh that outlives Today disappearing, and skips work when the feeds already on screen are still fresh.
    func startRefreshIfNeeded(feeds: [Feed]) {
        if Self.shouldRefresh(
            feeds: feeds.map {
                FeedFreshness(isEnabled: $0.isEnabled, isRemote: $0.remoteID != nil, lastFetchedAt: $0.lastFetchedAt)
            },
            lastSuccessfulRefresh: BackgroundRefreshCoordinator.lastSuccessfulRefresh,
            isRefreshing: isRefreshing
        ) {
            guard inFlightRefresh == nil else { return }
            inFlightIsFullRefresh = true
            inFlightRefresh = Task { await self.performRefresh(followsUp: false) }
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
        let task = Task { await self.performRefresh(followsUp: true) }
        inFlightRefresh = task
        await task.value
    }

    func clearError() { presentedError = nil }

    /// Whether Today should fetch. Uses the feeds already on screen, so opening Today does not load them again.
    static func shouldRefresh(
        feeds: [FeedFreshness],
        lastSuccessfulRefresh: Date?,
        now: Date = .now,
        staleInterval: TimeInterval = BackgroundRefreshCoordinator.staleInterval,
        isRefreshing: Bool
    ) -> Bool {
        if isRefreshing { return false }
        let localFeeds = feeds.filter { $0.isEnabled && !$0.isRemote }
        if localFeeds.contains(where: { $0.lastFetchedAt == nil }) { return true }
        if let last = lastSuccessfulRefresh, now.timeIntervalSince(last) < staleInterval {
            return false
        }
        if let lastFetched = localFeeds.compactMap(\.lastFetchedAt).max(),
           now.timeIntervalSince(lastFetched) < staleInterval {
            return false
        }
        return !localFeeds.isEmpty
    }

    private func performRefresh(followsUp: Bool) async {
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
        await BackgroundRefreshCoordinator.runExclusive(followsUp: followsUp) {
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
    /// Captions fill in after the deck draws. The featured preview is published with the card, so the title does not jump when the blurb arrives.
    private func scheduleCaptions() {
        let articles = remainingArticles
        guard !articles.isEmpty, let context else {
            captionTask?.cancel()
            captionStamp = Int.min
            cachedCaptions = [:]
            storyCaptions = [:]
            spokenCaptions = [:]
            prefetchedExcerpts = [:]
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
        let frame = FeaturedExcerptFrame(articleID: featuredExcerptID, text: featuredExcerpt)
            .advancing(to: featured?.id, preview: featured.flatMap(preparedExcerpt(for:)))
        if frame.articleID != featuredExcerptID || frame.text != featuredExcerpt {
            featuredExcerpt = frame.text
            featuredExcerptID = frame.articleID
        }
        let visibleCaptions = StoryCaptionPublish.visual(known: cachedCaptions, visibleIDs: articles.map(\.id))
        if visibleCaptions != storyCaptions {
            storyCaptions = visibleCaptions
        }
        let upcoming = articles.dropFirst().prefix(2).compactMap { article -> (id: UUID, sample: CardExcerptSample)? in
            guard prefetchedExcerpts[article.id] == nil else { return nil }
            return (
                article.id,
                CardExcerptSample(
                    aiSummary: ContentClassifier.cardExcerptSample(article.aiSummary),
                    summary: ContentClassifier.cardExcerptSample(article.summary)
                )
            )
        }
        let container = context.container
        let generation = captionGeneration
        captionTask?.cancel()
        captionTask = Task {
            async let built = StoryGrouping.captions(for: subjects, in: container)
            let previews = await Task.detached(priority: .userInitiated) {
                upcoming.map { item in
                    (
                        item.id,
                        ContentClassifier.cardExcerpt(aiSummary: item.sample.aiSummary, summary: item.sample.summary)
                    )
                }
            }.value
            let captions = await built
            guard !Task.isCancelled, generation == captionGeneration else { return }
            captionStamp = stamp
            cachedCaptions = captions
            spokenCaptions = captions
            for preview in previews where prefetchedExcerpts[preview.0] == nil {
                prefetchedExcerpts[preview.0] = preview.1.map(PrefetchedExcerpt.text) ?? .none
            }
        }
    }

    /// A warm preview is reused. The first time a story is featured, its excerpt is stripped once and kept.
    private func preparedExcerpt(for article: Article) -> String? {
        switch prefetchedExcerpts[article.id] {
        case .text(let text):
            return text
        case .none:
            return nil
        case nil:
            let text = article.displayExcerpt
            prefetchedExcerpts[article.id] = text.map(PrefetchedExcerpt.text) ?? .none
            return text
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

/// The fields Today needs to decide whether a source is stale. The list already has them.
struct FeedFreshness: Equatable, Sendable {
    var isEnabled: Bool
    var isRemote: Bool
    var lastFetchedAt: Date?
}

enum PrefetchedExcerpt: Equatable {
    case text(String)
    case none
}

/// The preview published with the featured card. Advancing shows the new blurb in that same update.
struct FeaturedExcerptFrame: Equatable {
    var articleID: UUID?
    var text: String?

    func advancing(to articleID: UUID?, preview: String?) -> FeaturedExcerptFrame {
        guard let articleID else { return FeaturedExcerptFrame(articleID: nil, text: nil) }
        return FeaturedExcerptFrame(articleID: articleID, text: preview)
    }
}

/// A similar-story line that is already known is shown with the card. One that arrives later is kept for the next deck.
enum StoryCaptionPublish {
    static func visual(known: [UUID: String], visibleIDs: [UUID]) -> [UUID: String] {
        var shown: [UUID: String] = [:]
        shown.reserveCapacity(visibleIDs.count)
        for id in visibleIDs {
            if let text = known[id] {
                shown[id] = text
            }
        }
        return shown
    }
}

/// VoiceOver hears a late caption only when it is not already on the card.
enum SpokenCaption {
    static func value(spoken: String?, visible: String?) -> String? {
        guard let spoken, !spoken.isEmpty, spoken != visible else { return nil }
        return spoken
    }
}
