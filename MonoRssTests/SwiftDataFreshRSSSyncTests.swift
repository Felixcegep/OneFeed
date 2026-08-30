import Foundation
import SwiftData
import Testing
@testable import MonoRss

private actor SwiftDataSyncAPI: FreshRSSAPI {
    private(set) var mutations: [(String, FreshRSSMutationKind)] = []

    func login(credentials: FreshRSSCredentials) async throws -> FreshRSSAuthResponse { .init(authToken: "token") }
    func subscriptions(authToken: String) async throws -> FreshRSSSubscriptionResponse { .init(subscriptions: []) }
    func itemIDs(streamID: String, authToken: String, unreadOnly: Bool, limit: Int, continuation: String?) async throws -> FreshRSSStreamItemIDsResponse { .init(itemRefs: []) }
    func itemContents(itemIDs: [String], authToken: String) async throws -> FreshRSSStreamContentsResponse { .init(items: []) }
    func streamContents(streamID: String, authToken: String, unreadOnly: Bool, limit: Int, continuation: String?) async throws -> FreshRSSStreamContentsResponse { .init(items: []) }
    func markRead(itemID: String, authToken: String) async throws { mutations.append((itemID, .markRead)) }
    func markUnread(itemID: String, authToken: String) async throws { mutations.append((itemID, .markUnread)) }
    func setStarred(itemID: String, authToken: String, starred: Bool) async throws { mutations.append((itemID, starred ? .star : .unstar)) }
    func recordedMutations() -> [(String, FreshRSSMutationKind)] { mutations }
}

@MainActor
struct SwiftDataFreshRSSSyncTests {
    private func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: Feed.self, Article.self, SyncAccount.self, PendingSyncMutation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func appSyncFlushesSwiftDataMutationAndUnstarsRestoredArticle() async throws {
        let context = try context()
        let credentials = InMemoryFreshRSSCredentialStore()
        let api = SwiftDataSyncAPI()
        let account = SyncAccount(provider: .freshRSS, serverURL: URL(string: "https://rss.example.test")!, username: "reader")
        context.insert(account)
        let savedCredentials = try FreshRSSCredentials(username: "reader", password: "api-password")
        await credentials.save(savedCredentials, for: account.id)

        let article = Article(guid: "one", title: "One", state: .saved, remoteID: "remote-one")
        context.insert(article)
        let service = FreshRSSSyncService(credentialStore: credentials, clientFactory: { _ in api })
        service.enqueueMutation(for: article, transition: .queued, in: context)
        #expect(try context.fetchCount(FetchDescriptor<PendingSyncMutation>()) == 1)

        try await service.sync(account: account, in: context)

        #expect(try context.fetchCount(FetchDescriptor<PendingSyncMutation>()) == 0)
        let mutations = await api.recordedMutations()
        #expect(mutations.count == 1)
        #expect(mutations.first?.0 == "remote-one")
        #expect(mutations.first?.1 == .unstar)
    }

    @Test func offlineBodySurvivesSwiftDataRoundTrip() throws {
        let context = try context()
        context.insert(Article(guid: "offline", title: "Offline", summary: "Cached summary", contentHTML: "<p>Cached body</p>"))
        try context.save()
        let article = try #require(context.fetch(FetchDescriptor<Article>()).first)
        #expect(article.readableHTML == "<p>Cached body</p>")
    }

    @Test func skipDoesNotEnqueueFreshRSSMutation() throws {
        let context = try context()
        let article = Article(guid: "skip", title: "Skip", state: .current, remoteID: "remote-skip")
        context.insert(article)
        FreshRSSSyncService().enqueueMutation(for: article, transition: .skipped, in: context)
        #expect(try context.fetchCount(FetchDescriptor<PendingSyncMutation>()) == 0)
    }

    @Test func disconnectClearsRemoteIDsSoFeedsCanRefreshLocally() async throws {
        let context = try context()
        let credentials = InMemoryFreshRSSCredentialStore()
        let account = SyncAccount(provider: .freshRSS, serverURL: URL(string: "https://rss.example.test")!, username: "reader")
        context.insert(account)
        await credentials.save(try FreshRSSCredentials(username: "reader", password: "api-password"), for: account.id)
        context.insert(Feed(title: "Remote", feedURL: URL(string: "https://example.test/rss")!, remoteID: "feed/https://example.test/rss"))

        try await FreshRSSSyncService(credentialStore: credentials).disconnect(account: account, in: context)

        #expect(try context.fetchCount(FetchDescriptor<SyncAccount>()) == 0)
        #expect(try context.fetch(FetchDescriptor<Feed>()).first?.remoteID == nil)
    }

    @Test func finishingSavedArticleEnqueuesUnstarAndMarkRead() throws {
        let context = try context()
        let article = Article(guid: "saved", title: "Saved", state: .saved, remoteID: "remote-saved", isRemoteStarred: true)
        context.insert(article)
        let viewModel = SavedViewModel(queue: ArticleQueueService(), freshRSSService: FreshRSSSyncService())
        viewModel.configure(with: context)
        viewModel.finishReading(article, as: .read)

        #expect(article.state == .read)
        #expect(article.isRemoteStarred == false)
        let mutations = try context.fetch(FetchDescriptor<PendingSyncMutation>(sortBy: [SortDescriptor(\.createdAt)]))
        #expect(mutations.map(\.kind) == [.unstar, .markRead])
    }

    @Test func appRegistersOneFeedURLSchemeAndAllowsCleartextHTTP() {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes.contains("onefeed"))
        let ats = Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any] ?? [:]
        #expect(ats["NSAllowsArbitraryLoads"] as? Bool == true)
        // iOS ignores NSAllowsArbitraryLoads when any of these companion keys are present,
        // which re-blocks HTTP FreshRSS hosts the way NetNewsWire does not.
        #expect(ats["NSAllowsLocalNetworking"] == nil)
        #expect(ats["NSAllowsArbitraryLoadsInWebContent"] == nil)
        #expect(ats["NSAllowsArbitraryLoadsForMedia"] == nil)
    }

    @Test func syncFollowsItemIDContinuationPages() async throws {
        let context = try context()
        let credentials = InMemoryFreshRSSCredentialStore()
        let api = PagingSyncAPI()
        let account = SyncAccount(provider: .freshRSS, serverURL: URL(string: "http://rss.local")!, username: "reader")
        context.insert(account)
        await credentials.save(try FreshRSSCredentials(username: "reader", password: "api-password"), for: account.id)

        try await FreshRSSSyncService(credentialStore: credentials, clientFactory: { _ in api }).sync(account: account, in: context)

        #expect(await api.recordedPages() == [nil, "cursor-2"])
        let articles = try context.fetch(FetchDescriptor<Article>(sortBy: [SortDescriptor(\.remoteID)]))
        #expect(articles.map(\.remoteID) == ["item-1", "item-2"])
    }

    @Test func backgroundRefreshSyncsLocalFeedsAndFreshRSS() async throws {
        let context = try context()
        let feeds = RecordingFeedRepository()
        let sync = RecordingFreshRSSService()
        context.insert(SyncAccount(provider: .freshRSS, serverURL: URL(string: "http://rss.local")!, username: "reader"))

        await BackgroundRefreshCoordinator.refresh(in: context, feedService: feeds, freshRSSService: sync)

        #expect(feeds.refreshed)
        #expect(sync.synced)
    }
}

private actor PagingSyncAPI: FreshRSSAPI {
    private(set) var pages: [String?] = []

    func login(credentials: FreshRSSCredentials) async throws -> FreshRSSAuthResponse { .init(authToken: "token") }
    func subscriptions(authToken: String) async throws -> FreshRSSSubscriptionResponse {
        .init(subscriptions: [.init(id: "feed/http://example.test/rss", title: "Example", feedURL: URL(string: "http://example.test/rss"), htmlURL: URL(string: "http://example.test"))])
    }
    func itemIDs(streamID: String, authToken: String, unreadOnly: Bool, limit: Int, continuation: String?) async throws -> FreshRSSStreamItemIDsResponse {
        .init(itemRefs: [])
    }
    func itemContents(itemIDs: [String], authToken: String) async throws -> FreshRSSStreamContentsResponse {
        .init(items: [])
    }
    func streamContents(streamID: String, authToken: String, unreadOnly: Bool, limit: Int, continuation: String?) async throws -> FreshRSSStreamContentsResponse {
        pages.append(continuation)
        if continuation == nil {
            return .init(items: [FreshRSSItem(id: "item-1", title: "Title item-1")], continuation: "cursor-2")
        }
        return .init(items: [FreshRSSItem(id: "item-2", title: "Title item-2")])
    }
    func markRead(itemID: String, authToken: String) async throws {}
    func markUnread(itemID: String, authToken: String) async throws {}
    func setStarred(itemID: String, authToken: String, starred: Bool) async throws {}
    func recordedPages() -> [String?] { pages }
}

@MainActor
private final class RecordingFeedRepository: FeedRepository {
    private(set) var refreshed = false
    func addSource(from input: String, in context: ModelContext) async throws -> Feed {
        Feed(title: input, feedURL: URL(string: "http://example.test/rss")!)
    }
    func refresh(_ feed: Feed, in context: ModelContext) async throws {}
    func refreshAll(in context: ModelContext) async throws { refreshed = true }
}

@MainActor
private final class RecordingFreshRSSService: FreshRSSSyncing {
    private(set) var synced = false
    func connect(serverURL: URL, username: String, password: String, in context: ModelContext) async throws -> SyncAccount {
        SyncAccount(provider: .freshRSS, serverURL: serverURL, username: username)
    }
    func disconnect(account: SyncAccount, in context: ModelContext) async throws {}
    func sync(account: SyncAccount, in context: ModelContext) async throws { synced = true }
    func enqueueMutation(for article: Article, transition: ArticleState, in context: ModelContext) {}
}
