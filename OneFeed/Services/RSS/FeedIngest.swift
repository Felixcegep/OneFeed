import Foundation
import SwiftData

extension LibraryIngestActor {
    func refreshLocalFeeds(
        session: URLSession,
        parser: FeedParser,
        youtubeMetadata: YouTubeMetadataService,
        progress: RefreshProgressSink
    ) async throws {
        modelContext.autosaveEnabled = false
        let feeds = try modelContext.fetch(FetchDescriptor<Feed>(predicate: #Predicate { $0.isEnabled && $0.remoteID == nil }))
            .filter(\.refreshesOverRSS)
        await progress.begin(phase: .sources, total: feeds.count)
        let requests = feeds.map {
            FeedService.RemoteFeedRequest(id: $0.id, url: $0.feedURL, etag: $0.etag, lastModified: $0.lastModified)
        }
        let feedsByID = Dictionary(uniqueKeysWithValues: feeds.map { ($0.id, $0) })
        var identityIndex = ArticleIdentityIndex(articles: identityArticles())
        var succeeded = 0
        var insertedCount = 0
        var firstError: Error?
        await withTaskGroup(of: FeedService.FetchOutcome.self) { group in
            var next = 0
            func startOne() {
                guard next < requests.count else { return }
                let request = requests[next]
                next += 1
                group.addTask {
                    do {
                        let loaded = try await FeedService.download(request, session: session, parser: parser)
                        return FeedService.FetchOutcome(id: request.id, loaded: loaded, cancelled: false, transient: false, errorDescription: nil)
                    } catch {
                        return FeedService.FetchOutcome(
                            id: request.id,
                            loaded: nil,
                            cancelled: error.isCancellation,
                            transient: error.isTransientNetwork,
                            errorDescription: error.localizedDescription
                        )
                    }
                }
            }
            for _ in 0..<min(FeedService.maxConcurrentFetches, requests.count) {
                startOne()
            }
            for await outcome in group {
                startOne()
                guard let feed = feedsByID[outcome.id] else { continue }
                do {
                    if Task.isCancelled {
                        group.cancelAll()
                        firstError = firstError ?? CancellationError()
                        await progress.finishItem(newArticles: 0)
                        continue
                    }
                    if let loaded = outcome.loaded {
                        let added = try await apply(
                            loaded,
                            to: feed,
                            youtubeMetadata: youtubeMetadata,
                            fetchDurations: false,
                            index: &identityIndex
                        )
                        insertedCount += added
                        succeeded += 1
                        await progress.finishItem(newArticles: added)
                    } else {
                        feed.lastFetchedAt = .now
                        if outcome.cancelled {
                            group.cancelAll()
                            firstError = firstError ?? CancellationError()
                        } else if !outcome.transient {
                            firstError = firstError ?? FeedService.FeedRefreshFailure(
                                outcome.errorDescription ?? "The source returned an unexpected response."
                            )
                        }
                        await progress.finishItem(newArticles: 0)
                    }
                } catch {
                    feed.lastFetchedAt = .now
                    if error.isCancellation {
                        group.cancelAll()
                        firstError = firstError ?? error
                    } else if !error.isTransientNetwork {
                        firstError = firstError ?? error
                    }
                    await progress.finishItem(newArticles: 0)
                }
                await Task.yield()
            }
        }
        await enrichMissingYouTubeDurations(
            limit: FeedService.durationBackfillLimit,
            youtubeMetadata: youtubeMetadata,
            persist: false
        )
        if insertedCount > 0 {
            _ = try? ArticleIdentity.mergeDuplicates(in: modelContext, persist: false)
        }
        try persistIfNeeded()
        if succeeded == 0, let firstError { throw firstError }
    }

    func applyDownload(feedID: UUID, loaded: FeedService.LoadedFeed, youtubeMetadata: YouTubeMetadataService) async throws {
        modelContext.autosaveEnabled = false
        guard let feed = try feed(id: feedID) else { return }
        var index = ArticleIdentityIndex(articles: identityArticles())
        _ = try await apply(loaded, to: feed, youtubeMetadata: youtubeMetadata, fetchDurations: false, index: &index)
        await enrichMissingYouTubeDurations(
            limit: FeedService.durationBackfillLimit,
            youtubeMetadata: youtubeMetadata,
            persist: false
        )
        try persistIfNeeded()
    }

    func ingestParsedArticles(feedID: UUID, articles: [ParsedArticle], youtubeMetadata: YouTubeMetadataService) async throws {
        modelContext.autosaveEnabled = false
        guard let feed = try feed(id: feedID) else { return }
        var index = ArticleIdentityIndex(articles: identityArticles())
        _ = try await insert(articles, into: feed, youtubeMetadata: youtubeMetadata, fetchDurations: false, index: &index)
        await enrichMissingYouTubeDurations(
            limit: FeedService.durationBackfillLimit,
            youtubeMetadata: youtubeMetadata,
            persist: false
        )
        try persistIfNeeded()
    }

    func enrichMissingYouTubeDurations(limit: Int, youtubeMetadata: YouTubeMetadataService, persist: Bool) async {
        let missing = articlesMissingYouTubeDuration(limit: limit)
        guard !missing.isEmpty else { return }

        let deckItems = (try? modelContext.fetch(FetchDescriptor<DailyDeckItem>())) ?? []
        var iterator = missing.makeIterator()
        var inFlight = 0
        await withTaskGroup(of: (UUID, String?, Int?).self) { group in
            func enqueue() {
                while inFlight < FeedService.durationConcurrency, let article = iterator.next() {
                    let id = article.id
                    let videoID = article.videoID
                        ?? YouTubeProcessor.parseVideoID(from: article.url)
                        ?? YouTubeProcessor.parseVideoID(fromGUID: article.guid)
                    guard let videoID else { continue }
                    inFlight += 1
                    group.addTask {
                        (id, videoID, await youtubeMetadata.fetchDuration(videoID: videoID, allowWatchHTML: false))
                    }
                }
            }
            enqueue()
            for await (id, videoID, duration) in group {
                inFlight -= 1
                if let article = missing.first(where: { $0.isStored && $0.id == id }) {
                    if let videoID, article.videoID == nil {
                        article.videoID = videoID
                    }
                    if let duration, duration > 0 {
                        _ = YouTubeProcessor.applyFetchedDuration(duration, to: article, deckItems: deckItems)
                    }
                }
                enqueue()
            }
        }
        if persist {
            try? persistIfNeeded()
        }
    }

    @discardableResult
    private func apply(
        _ loaded: FeedService.LoadedFeed,
        to feed: Feed,
        youtubeMetadata: YouTubeMetadataService,
        fetchDurations: Bool,
        index: inout ArticleIdentityIndex
    ) async throws -> Int {
        switch loaded {
        case .notModified:
            feed.lastFetchedAt = .now
            return 0
        case .updated(let parsed, let etag, let lastModified):
            feed.title = parsed.title
            feed.websiteURL = parsed.websiteURL ?? feed.websiteURL
            feed.etag = etag
            feed.lastModified = lastModified
            feed.lastFetchedAt = .now
            return try await insert(
                parsed.articles,
                into: feed,
                youtubeMetadata: youtubeMetadata,
                fetchDurations: fetchDurations,
                index: &index
            )
        }
    }

    @discardableResult
    private func insert(
        _ parsedArticles: [ParsedArticle],
        into feed: Feed,
        youtubeMetadata: YouTubeMetadataService,
        fetchDurations: Bool,
        index: inout ArticleIdentityIndex
    ) async throws -> Int {
        let feedKind = ContentKind(rawValue: feed.contentKind) ?? .article
        let filterRules = FilterEngine.blockedWordRules(from: feed.blockedWords)
        let feedContext = FilterFeedContext(title: feed.title, url: feed.feedURL.absoluteString)
        var inserted = 0
        let cutoff = ArticleRetentionService.ingestCutoff(isFirstPopulate: isEmptyFeed(feed))
        for (offset, parsed) in parsedArticles.enumerated() {
            if offset > 0, offset.isMultiple(of: 24) {
                await Task.yield()
            }
            if let existing = index.existing(
                url: parsed.url,
                guid: parsed.guid,
                feedID: feed.id,
                videoID: YouTubeProcessor.parseVideoID(from: parsed.url)
                    ?? YouTubeProcessor.parseVideoID(fromGUID: parsed.guid)
            ) {
                if existing.feed == nil { existing.feed = feed }
                continue
            }
            if let cutoff, parsed.publishedAt < cutoff { continue }
            let classified = ContentClassifier.classify(
                url: parsed.url,
                title: parsed.title,
                summary: parsed.summary,
                contentHTML: parsed.contentHTML,
                enclosureMIME: parsed.enclosureMIME,
                durationSeconds: parsed.durationSeconds,
                feedType: feedKind
            )

            if classified.kind == .youtube {
                if classified.isShort, !feed.includeShorts { continue }
                if !feed.includeVideos { continue }

                let videoID = classified.videoID ?? YouTubeProcessor.parseVideoID(fromGUID: parsed.guid)
                var duration = classified.durationSeconds
                if fetchDurations, !classified.isShort, duration == nil, let videoID {
                    duration = await youtubeMetadata.fetchDuration(videoID: videoID)
                }
                if !YouTubeProcessor.shouldKeep(durationSeconds: duration, minVideoSeconds: feed.minVideoSeconds) {
                    continue
                }

                let filterEntry = FeedService.filterEntry(from: parsed)
                let filterResult = FilterEngine.apply(rules: filterRules, entry: filterEntry, feed: feedContext)
                if filterResult.drop { continue }

                let minutes = (duration ?? 0) > 0
                    ? ContentClassifier.consumeMinutes(entryType: classified.kind, words: 0, durationSeconds: duration)
                    : classified.estimatedMinutes
                let article = Article(
                    guid: parsed.guid,
                    title: parsed.title,
                    url: parsed.url ?? videoID.flatMap { YouTubeProcessor.watchURL(for: $0) },
                    author: parsed.author,
                    publishedAt: parsed.publishedAt,
                    summary: parsed.summary,
                    contentHTML: parsed.contentHTML,
                    estimatedReadingMinutes: minutes,
                    state: filterResult.star ? .saved : .queued,
                    isRemoteStarred: filterResult.star,
                    contentKind: classified.kind.rawValue,
                    durationSeconds: duration ?? 0,
                    imageURL: parsed.imageURL ?? videoID.flatMap { YouTubeProcessor.thumbnailURL(for: $0) },
                    videoID: videoID,
                    enclosureURL: parsed.enclosureURL,
                    enclosureMIME: parsed.enclosureMIME,
                    feed: feed
                )
                modelContext.insert(article)
                index.register(article)
                inserted += 1
            } else {
                let filterEntry = FeedService.filterEntry(from: parsed)
                let filterResult = FilterEngine.apply(rules: filterRules, entry: filterEntry, feed: feedContext)
                if filterResult.drop { continue }

                let article = Article(
                    guid: parsed.guid,
                    title: parsed.title,
                    url: parsed.url,
                    author: parsed.author,
                    publishedAt: parsed.publishedAt,
                    summary: parsed.summary,
                    contentHTML: parsed.contentHTML,
                    estimatedReadingMinutes: classified.estimatedMinutes,
                    state: filterResult.star ? .saved : .queued,
                    isRemoteStarred: filterResult.star,
                    contentKind: classified.kind.rawValue,
                    durationSeconds: classified.durationSeconds ?? 0,
                    imageURL: parsed.imageURL,
                    videoID: classified.videoID,
                    enclosureURL: parsed.enclosureURL,
                    enclosureMIME: parsed.enclosureMIME,
                    feed: feed
                )
                modelContext.insert(article)
                index.register(article)
                inserted += 1
            }
        }
        return inserted
    }

    private func feed(id: UUID) throws -> Feed? {
        try modelContext.fetch(FetchDescriptor<Feed>(predicate: #Predicate { $0.id == id })).first
    }

    private func isEmptyFeed(_ feed: Feed) -> Bool {
        let feedID = feed.id
        var descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.feed?.id == feedID })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.isEmpty ?? true
    }

    private func articlesMissingYouTubeDuration(limit: Int) -> [Article] {
        let deckItems = ((try? modelContext.fetch(FetchDescriptor<DailyDeckItem>())) ?? [])
            .sorted { $0.position < $1.position }
        var targets: [Article] = []
        var seen = Set<UUID>()
        for item in deckItems {
            guard let article = item.article, article.isStored else { continue }
            guard article.contentKind == "youtube", article.durationSeconds <= 0 else { continue }
            if seen.insert(article.id).inserted {
                targets.append(article)
            }
            if targets.count >= limit { return targets }
        }
        let youtube = "youtube"
        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { article in
                article.contentKind == youtube && article.durationSeconds <= 0
            }
        )
        descriptor.fetchLimit = max(limit * 2, 16)
        descriptor.sortBy = [SortDescriptor(\.publishedAt, order: .reverse)]
        let extra = ((try? modelContext.fetch(descriptor)) ?? []).filter { article in
            article.isStored && !seen.contains(article.id)
        }
        for article in extra {
            targets.append(article)
            if targets.count >= limit { break }
        }
        return targets
    }
}
