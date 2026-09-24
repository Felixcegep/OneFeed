import Foundation
import SwiftData
import Testing
@testable import OneFeed

@MainActor
struct SourceDetailTests {
    private func context() throws -> ModelContext {
        try InMemoryStore.makeContext()
    }

    @Test func middleIdentityChangesTheListToken() {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let middle = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let last = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let replacement = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let original = ListIdentity.token(ids: [first, middle, last])
        #expect(ListIdentity.token(ids: [first, middle, last]) == original)
        #expect(ListIdentity.token(ids: [first, replacement, last]) != original)
    }

    @Test func recentStoriesAreTheNewestTwenty() throws {
        let context = try context()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        context.insert(feed)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<30 {
            context.insert(Article(
                guid: "story-\(index)",
                title: "Story \(index)",
                publishedAt: start.addingTimeInterval(Double(index) * 60),
                feed: feed
            ))
        }
        try context.save()

        let model = SourceDetailViewModel(feed: feed, context: context, freshRSSService: IdleFreshRSS())
        let recent = model.recentArticles
        let loads = model.recentStoryLoads
        #expect(recent.count == 20)
        #expect(recent.first?.guid == "story-29")
        #expect(recent.last?.guid == "story-10")
        #expect(model.recentArticles.map(\.guid) == recent.map(\.guid))
        #expect(model.recentStoryLoads == loads)

        model.blockedWords = "Sponsored"
        model.commitBlockedWords()
        #expect(model.recentStoryLoads == loads)
        #expect(model.recentArticles.map(\.guid) == recent.map(\.guid))

        context.insert(Article(
            guid: "story-new",
            title: "Newest",
            publishedAt: start.addingTimeInterval(10_000_000),
            feed: feed
        ))
        try context.save()
        #expect(model.recentStoryLoads == loads + 1)
        #expect(model.recentArticles.first?.guid == "story-new")
        #expect(model.recentArticles.count == 20)
    }

    @Test func blockedWordsWaitUntilTypingPauses() {
        let context = try context()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        context.insert(feed)
        let model = SourceDetailViewModel(feed: feed, context: context, freshRSSService: IdleFreshRSS())

        model.blockedWords = "AI"
        model.blockedWords = "AI, Sponsored"
        #expect(feed.blockedWords.isEmpty)
        model.commitBlockedWords()
        #expect(feed.blockedWords == "AI, Sponsored")
        model.commitBlockedWords()
        #expect(feed.blockedWords == "AI, Sponsored")
    }

    @Test func checkingAFolderDoesNotReloadTheFolderList() throws {
        let context = try context()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!, folderName: "Philosophy")
        let other = Feed(title: "Other", feedURL: URL(string: "https://other.test/rss")!, folderName: "Development")
        context.insert(feed)
        context.insert(other)
        try context.save()
        let model = SourceDetailViewModel(feed: feed, context: context, freshRSSService: IdleFreshRSS())
        let loads = model.folderListLoads
        #expect(model.availableFolders.contains("Philosophy"))
        #expect(model.availableFolders.contains("Development"))

        model.toggleFolder("Development")
        #expect(model.folderListLoads == loads)
        #expect(feed.containsFolder("Development"))
        #expect(feed.containsFolder("Philosophy"))

        model.toggleFolder("Development")
        #expect(model.folderListLoads == loads)
        #expect(!feed.containsFolder("Development"))
    }

    @Test func typingDoesNotRebuildFolderMembership() throws {
        let context = try context()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!, folderName: "Philosophy")
        context.insert(feed)
        try context.save()
        let model = SourceDetailViewModel(feed: feed, context: context, freshRSSService: IdleFreshRSS())
        #expect(model.sourceIsInFolder("Philosophy"))
        let builds = model.membershipBuilds
        #expect(model.sourceIsInFolder("philosophy"))
        #expect(model.membershipBuilds == builds)
        model.blockedWords = "Sponsored"
        #expect(model.sourceIsInFolder("Philosophy"))
        #expect(model.membershipBuilds == builds)
        model.toggleFolder("Development")
        #expect(model.sourceIsInFolder("Development"))
        #expect(model.membershipBuilds == builds + 1)
    }

    @Test func aSecondRemoveIsIgnoredWhileTheFirstIsRunning() async throws {
        let context = try context()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        context.insert(feed)
        try context.save()
        let service = HoldingFreshRSS()
        let model = SourceDetailViewModel(feed: feed, context: context, freshRSSService: service)

        let first = Task { await model.remove() }
        for _ in 0..<50 where service.removals == 0 {
            await Task.yield()
        }
        await model.remove()
        #expect(service.removals == 1)
        service.finish()
        await first.value
        #expect(service.removals == 1)
        #expect(try context.fetch(FetchDescriptor<Feed>()).isEmpty)
    }
}

@MainActor
private final class IdleFreshRSS: FreshRSSSyncing {
    func connect(serverURL: URL, username: String, password: String, in context: ModelContext) async throws -> SyncAccount {
        SyncAccount(provider: .freshRSS, serverURL: serverURL, username: username)
    }
    func disconnect(account: SyncAccount, in context: ModelContext) async throws {}
    func sync(account: SyncAccount, in context: ModelContext, progress: RefreshProgress?) async throws {}
    func enqueueMutation(for article: Article, transition: ArticleState, in context: ModelContext) {}
    func addSubscription(from input: String, folderName: String?, in context: ModelContext) async throws -> Feed {
        Feed(title: input, feedURL: URL(string: "https://source.test/rss")!)
    }
    func removeSubscription(_ feed: Feed, in context: ModelContext) async throws {}
    func subscribeLocalFeeds(in context: ModelContext) async throws {}
}

@MainActor
private final class HoldingFreshRSS: FreshRSSSyncing {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var removals = 0

    func connect(serverURL: URL, username: String, password: String, in context: ModelContext) async throws -> SyncAccount {
        SyncAccount(provider: .freshRSS, serverURL: serverURL, username: username)
    }
    func disconnect(account: SyncAccount, in context: ModelContext) async throws {}
    func sync(account: SyncAccount, in context: ModelContext, progress: RefreshProgress?) async throws {}
    func enqueueMutation(for article: Article, transition: ArticleState, in context: ModelContext) {}
    func addSubscription(from input: String, folderName: String?, in context: ModelContext) async throws -> Feed {
        Feed(title: input, feedURL: URL(string: "https://source.test/rss")!)
    }
    func removeSubscription(_ feed: Feed, in context: ModelContext) async throws {
        removals += 1
        await withCheckedContinuation { continuations.append($0) }
        context.delete(feed)
        try context.save()
    }
    func subscribeLocalFeeds(in context: ModelContext) async throws {}

    func finish() {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}
