import Foundation
import SwiftData
import Testing
@testable import OneFeed

@MainActor
struct RetentionAndExtractionTests {
    private func context() throws -> ModelContext {
        try InMemoryStore.makeContext()
    }

    @Test func purgeKeepsSavedAndRecentArticles() throws {
        let context = try context()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        context.insert(feed)
        let old = Article(guid: "old", title: "Old", publishedAt: .now.addingTimeInterval(-10 * 86_400), state: .queued, feed: feed)
        let kept = Article(guid: "saved", title: "Saved", publishedAt: .now.addingTimeInterval(-10 * 86_400), state: .saved, feed: feed)
        let fresh = Article(guid: "fresh", title: "Fresh", publishedAt: .now, state: .queued, feed: feed)
        let noted = Article(
            guid: "noted",
            title: "Noted",
            publishedAt: .now.addingTimeInterval(-10 * 86_400),
            state: .read,
            readingReactionRawValue: "",
            readingNote: "  The nonce repeats.  ",
            feed: feed
        )
        let readBare = Article(
            guid: "read",
            title: "Read",
            publishedAt: .now.addingTimeInterval(-10 * 86_400),
            state: .read,
            readingReactionRawValue: "",
            readingNote: "",
            feed: feed
        )
        context.insert(old)
        context.insert(kept)
        context.insert(fresh)
        context.insert(noted)
        context.insert(readBare)
        try context.save()

        #expect(!noted.readingNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(noted.readingReactionRawValue.isEmpty)
        #expect(readBare.readingNote.isEmpty)
        #expect(readBare.readingReactionRawValue.isEmpty)
        #expect(kept.state == .saved)

        let removed = try ArticleRetentionService().purge(in: context, olderThanDays: 7)
        #expect(removed == 2)
        let remaining = try context.fetch(FetchDescriptor<Article>(sortBy: [SortDescriptor(\.guid)]))
        #expect(remaining.map(\.guid) == ["fresh", "noted", "saved"])
        #expect(remaining.first { $0.guid == "noted" }?.readingNote == "  The nonce repeats.  ")
        #expect(remaining.first { $0.guid == "saved" }?.state == .saved)
    }

    @Test func purgeKeepsTodayDeckItemsAndHonorsForever() throws {
        let context = try context()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        context.insert(feed)
        let deckArticle = Article(guid: "deck", title: "Deck", publishedAt: .now.addingTimeInterval(-10 * 86_400), state: .current, feed: feed)
        let old = Article(guid: "old", title: "Old", publishedAt: .now.addingTimeInterval(-10 * 86_400), state: .queued, feed: feed)
        context.insert(deckArticle)
        context.insert(old)
        let deck = DailyDeck(dayStart: Calendar.current.startOfDay(for: .now))
        context.insert(deck)
        context.insert(DailyDeckItem(position: 1, status: .current, article: deckArticle, deck: deck))
        try context.save()

        #expect(try ArticleRetentionService().purge(in: context, olderThanDays: 0) == 0)
        let removed = try ArticleRetentionService().purge(in: context, olderThanDays: 7)
        #expect(removed == 1)
        let remaining = try context.fetch(FetchDescriptor<Article>(sortBy: [SortDescriptor(\.guid)]))
        #expect(remaining.map(\.guid) == ["deck"])
    }

    @Test func firstImportCutoffIsSevenDaysThenFollowsRetention() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let first = ArticleRetentionService.ingestCutoff(isFirstPopulate: true, now: now)
        #expect(first == now.addingTimeInterval(-7 * 86_400))
    }

    @Test func queuePlanKeepsTheSavedStoryAndSplitsTheVideo() {
        let saved = Article(guid: "saved", title: "Essay", url: URL(string: "https://example.com/essay"), state: .saved, contentKind: "article")
        let copy = Article(guid: "copy", title: "Essay copy", url: URL(string: "https://example.com/essay"), state: .queued, contentKind: "article")
        let video = Article(guid: "video", title: "Talk", url: URL(string: "https://example.com/talk"), state: .saved, contentKind: "youtube")
        let collapsed = ArticleIdentity.collapsingDuplicates([video, saved, copy])
        let plan = QueueListPlan.make(from: [video, saved, copy].map(queueSnap), query: "")
        #expect(plan.collapsedIDs == collapsed.map(\.id))
        #expect(plan.upNext == video.id)
        #expect(plan.videos.isEmpty)
        #expect(plan.articles == [saved.id])
        #expect(plan.subtitle == "2 in queue · 1 video")
        let datesOnly = [video, saved, copy].map { article in
            var snap = queueSnap(article)
            snap.title = ""
            snap.readingNote = ""
            snap.reactionRaw = ""
            snap.feedTitle = nil
            snap.author = nil
            return snap
        }
        let quiet = QueueListPlan.make(from: datesOnly, query: "")
        #expect(quiet.upNext == plan.upNext)
        #expect(quiet.articles == plan.articles)
        #expect(QueueListPlan.make(from: [video, saved, copy].map(queueSnap), query: "Essay").articles == [saved.id])
    }

    private func queueSnap(_ article: Article) -> QueueStorySnap {
        QueueStorySnap(
            id: article.id,
            publishedAt: article.publishedAt,
            title: article.title,
            readingNote: article.readingNote,
            reactionRaw: article.readingReactionRawValue,
            feedTitle: article.feed?.title,
            hasFeed: article.feed != nil,
            url: article.url,
            author: article.author,
            contentKind: article.contentKind,
            videoID: article.videoID,
            guid: article.guid,
            hasRemoteID: article.remoteID != nil,
            stateRaw: article.stateRawValue,
            isRemoteStarred: article.isRemoteStarred
        )
    }

    @Test func historyDayKeepsNewestFirst() throws {
        let context = try InMemoryStore.makeContext()
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let older = Article(guid: "older", title: "Older", publishedAt: day, state: .read)
        older.completedAt = day
        let newer = Article(guid: "newer", title: "Newer", publishedAt: day, state: .read)
        newer.completedAt = day.addingTimeInterval(3_600)
        context.insert(older)
        context.insert(newer)

        let days = HistoryViewModel.days(from: [older, newer])
        #expect(days.count == 1)
        #expect(days[0].articles.map(\.title) == ["Newer", "Older"])
        let plans = HistoryViewModel.dayPlans(from: [older, newer].map(historySnap), query: "")
        #expect(plans.count == 1)
        #expect(plans[0].articleIDs == [newer.id, older.id])
        #expect(plans[0].day == days[0].day)
        let datesOnly = [older, newer].map { article in
            HistoryStorySnap(
                id: article.id,
                completedAt: article.completedAt,
                publishedAt: article.publishedAt,
                title: "",
                readingNote: "",
                reactionRaw: "",
                feedTitle: nil,
                url: nil,
                author: nil,
                contentKind: ""
            )
        }
        #expect(HistoryViewModel.dayPlans(from: datesOnly, query: "").map(\.articleIDs) == [newer.id, older.id])
        #expect(HistoryViewModel.dayPlans(from: [older, newer].map(historySnap), query: "Newer").flatMap(\.articleIDs) == [newer.id])
    }

    private func historySnap(_ article: Article) -> HistoryStorySnap {
        HistoryStorySnap(
            id: article.id,
            completedAt: article.completedAt,
            publishedAt: article.publishedAt,
            title: article.title,
            readingNote: article.readingNote,
            reactionRaw: article.readingReactionRawValue,
            feedTitle: article.feed?.title,
            url: article.url,
            author: article.author,
            contentKind: article.contentKind
        )
    }

    @Test func cancelledRefreshIsNotShownToTheUser() {
        #expect(RefreshFailure.message(for: CancellationError()) == nil)
        #expect(RefreshFailure.message(for: URLError(.cancelled)) == nil)
        #expect(RefreshFailure.message(for: URLError(.timedOut)) == nil)
        #expect(RefreshFailure.message(for: URLError(.cannotConnectToHost)) == nil)
        #expect(RefreshFailure.message(for: URLError(.notConnectedToInternet)) == nil)
        #expect(RefreshFailure.message(for: FeedServiceError.http(500)) == "The source could not be loaded (HTTP 500).")
        #expect(RefreshFailure.message(for: NSError(domain: "SwiftData", code: 1)) == "Couldn’t refresh.")
    }

    @Test func readerFailuresStayInPlainLanguage() {
        #expect(ReaderFailure.message(for: GeminiClientError.missingAPIKey) == "Add a Google AI Studio API key in Settings.")
        #expect(ReaderFailure.message(for: URLError(.timedOut)) == "The connection dropped. Try again.")
        #expect(ReaderFailure.message(for: FeedServiceError.http(500)) == "That did not finish. Try again.")
    }

    @Test func queueErrorsUseAppSentences() {
        #expect(UserFacingFailure.message(for: QueueLinkError.invalidAddress, fallback: "Couldn’t add that link.") == "That doesn’t look like a link.")
        let system = NSError(domain: "SwiftData", code: 1)
        #expect(UserFacingFailure.message(for: system, fallback: "Couldn’t update Queue.") == "Couldn’t update Queue.")
        #expect(UserFacingFailure.message(for: URLError(.notConnectedToInternet), fallback: "Couldn’t sync the library.") == "Couldn’t sync the library.")
        #expect(GoogleDriveOAuthError.tokenExchangeFailed("invalid_grant").errorDescription == "Google Drive sign-in failed. Try again.")
    }

    @Test func automaticExtractSkipsSubstantialRSS() {
        let policy = ArticleExtractionPolicy()
        let long = Array(repeating: "word", count: 420).joined(separator: " ")
        #expect(policy.shouldFetchPage(rssHTML: "<p>\(long)</p>", kind: "article") == false)
        #expect(policy.shouldFetchPage(rssHTML: "<p>Short excerpt of a longer essay.</p>", kind: "article") == true)
        let medium = Array(repeating: "word", count: 90).joined(separator: " ")
        #expect(policy.shouldFetchPage(rssHTML: "<p>\(medium)</p>", kind: "article") == true)
        #expect(policy.shouldFetchPage(rssHTML: "<p>Short</p>", kind: "youtube") == false)
        var off = ArticleExtractionPolicy()
        off.mode = .off
        #expect(off.shouldFetchPage(rssHTML: "<p>Short</p>", kind: "article") == false)
    }

    @Test @MainActor func aFullArticleDoesNotStartAPageFetch() async throws {
        let context = try InMemoryStore.makeContext()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        context.insert(feed)
        let long = Array(repeating: "word", count: 420).joined(separator: " ")
        let article = Article(
            guid: "full",
            title: "Full",
            url: URL(string: "https://source.test/story")!,
            contentHTML: "<p>\(long)</p>",
            feed: feed
        )
        context.insert(article)
        try context.save()
        let model = ReaderViewModel(article: article)
        await model.enrichReadableHTML()
        #expect(model.isExtracting == false)
        #expect(article.contentHTML == "<p>\(long)</p>")
    }

    @Test @MainActor func readerRedrawDoesNotLookUpTheImportedFileAgain() {
        let article = Article(guid: "story", title: "Story", url: URL(string: "https://source.test/story")!)
        let model = ReaderViewModel(article: article)
        #expect(model.importedFileURL == nil)
        let resolves = model.fileResolves
        #expect(model.importedFileURL == nil)
        #expect(model.fileResolves == resolves)
    }

    @Test func swiftReadabilityExtractsArticleAndAbsoluteURLs() throws {
        let html = """
        <!doctype html><html><head><title>Site chrome</title></head>
        <body>
          <nav><a href="/home">Home</a><a href="/ads">Advertise</a></nav>
          <article>
            <h1>The real story</h1>
            <p>This paragraph is long enough that Readability should treat it as the article because it contains many words about the actual topic rather than navigation chrome or related links.</p>
            <p>A second paragraph continues the article with more substantial text so scoring prefers this region. <a href="/next">Continue</a></p>
            <img src="/photo.jpg" alt="photo">
          </article>
          <footer>Copyright subscribe newsletter</footer>
        </body></html>
        """
        let extracted = SwiftReadabilityExtractor().extract(
            fromHTML: html,
            pageURL: URL(string: "https://example.com/post")!
        )
        let content = try #require(extracted)
        #expect(content.contains("The real story") || content.contains("real story"))
        #expect(content.contains("https://example.com/photo.jpg"))
        #expect(content.contains("https://example.com/next"))
        #expect(!content.contains("Advertise"))
    }

    @Test func enrichUpcomingExtractsOnlyCurrentAndNextQueued() async throws {
        let context = try context()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        context.insert(feed)
        var articles: [Article] = []
        for index in 1...4 {
            let article = Article(
                guid: "g-\(index)",
                title: "Story \(index)",
                url: URL(string: "https://source.test/\(index)")!,
                publishedAt: .now.addingTimeInterval(Double(-index * 60)),
                summary: "Short",
                contentHTML: "<p>Short</p>",
                feed: feed
            )
            context.insert(article)
            articles.append(article)
        }
        let deck = DailyDeck(dayStart: Calendar.current.startOfDay(for: .now))
        context.insert(deck)
        for (index, article) in articles.enumerated() {
            context.insert(DailyDeckItem(
                position: index + 1,
                status: index == 0 ? .current : .queued,
                article: article,
                deck: deck
            ))
        }
        try context.save()

        let extractor = RecordingExtractor()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubExtractURLProtocol.self]
        StubExtractURLProtocol.body = "<html><body><p>Downloaded page with enough words to keep.</p></body></html>"
        let session = URLSession(configuration: config)
        let service = ArticleExtractionService(session: session, extractor: extractor)
        await service.enrichUpcoming(in: context, from: deck.items.first { $0.position == 1 }, extraQueued: 2)

        #expect(extractor.urls == [
            URL(string: "https://source.test/1")!,
            URL(string: "https://source.test/2")!,
            URL(string: "https://source.test/3")!,
        ])
        #expect(articles[0].contentHTML?.contains("Extracted https://source.test/1") == true)
        #expect(articles[0].estimatedReadingMinutes == 3)
        #expect(articles[0].timedDurationPhrase == "3 min read")
        #expect(articles[3].contentHTML == "<p>Short</p>")
        #expect(articles[3].timedDurationPhrase == nil)
    }
}

private final class RecordingExtractor: ArticleExtracting, @unchecked Sendable {
    var urls: [URL] = []

    func extract(fromHTML html: String, pageURL: URL) -> String? {
        urls.append(pageURL)
        let body = Array(repeating: "word", count: 500).joined(separator: " ")
        return "<p>Extracted \(pageURL.absoluteString) \(body)</p>"
    }
}

private final class StubExtractURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = "<html></html>"

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url ?? URL(string: "https://source.test/")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
