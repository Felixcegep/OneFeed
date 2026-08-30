import Foundation
import SwiftData

@MainActor
protocol FreshRSSSyncing: AnyObject {
    func connect(serverURL: URL, username: String, password: String, in context: ModelContext) async throws -> SyncAccount
    func disconnect(account: SyncAccount, in context: ModelContext) async throws
    func sync(account: SyncAccount, in context: ModelContext) async throws
    func enqueueMutation(for article: Article, transition: ArticleState, in context: ModelContext)
}

@MainActor
final class FreshRSSSyncService {
    private let credentialStore: any FreshRSSCredentialStore
    private let clientFactory: @Sendable (FreshRSSConfiguration) -> any FreshRSSAPI

    init(
        credentialStore: any FreshRSSCredentialStore = KeychainFreshRSSCredentialStore(),
        clientFactory: @escaping @Sendable (FreshRSSConfiguration) -> any FreshRSSAPI = { FreshRSSClient(configuration: $0) }
    ) {
        self.credentialStore = credentialStore
        self.clientFactory = clientFactory
    }

    func connect(serverURL: URL, username: String, password: String, in context: ModelContext) async throws -> SyncAccount {
        let configuration = try FreshRSSConfiguration(baseURL: serverURL, username: username)
        let credentials = try FreshRSSCredentials(username: username, password: password)
        let client = clientFactory(configuration)
        _ = try await client.login(credentials: credentials)

        let freshRSS = SyncProvider.freshRSS.rawValue
        let existing = try context.fetch(FetchDescriptor<SyncAccount>(predicate: #Predicate { $0.providerRawValue == freshRSS })).first
        let account = existing ?? SyncAccount(provider: .freshRSS, serverURL: configuration.baseURL, username: credentials.username)
        account.serverURL = configuration.baseURL
        account.username = credentials.username
        account.isEnabled = true
        account.lastSyncError = nil
        if existing == nil { context.insert(account) }
        try await credentialStore.save(credentials, for: account.id)
        try context.save()
        try await sync(account: account, in: context)
        return account
    }

    func disconnect(account: SyncAccount, in context: ModelContext) async throws {
        try await credentialStore.delete(for: account.id)
        let remoteFeeds = try context.fetch(FetchDescriptor<Feed>(predicate: #Predicate { $0.remoteID != nil }))
        for feed in remoteFeeds { feed.remoteID = nil }
        context.delete(account)
        try context.save()
    }

    func sync(account: SyncAccount, in context: ModelContext) async throws {
        guard account.provider == .freshRSS, let serverURL = account.serverURL, let username = account.username,
              let credentials = try await credentialStore.load(for: account.id) else {
            throw FreshRSSSyncError.missingCredentials
        }
        let configuration = try FreshRSSConfiguration(baseURL: serverURL, username: username)
        let client = clientFactory(configuration)
        do {
            let token = try await client.login(credentials: credentials).authToken
            try await flushMutations(client: client, token: token, in: context)
            let subscriptions = try await client.subscriptions(authToken: token).subscriptions
            for subscription in subscriptions {
                let feed = try upsert(subscription: subscription, in: context)
                var continuation: String?
                var pages = 0
                repeat {
                    let page = try await client.streamContents(
                        streamID: subscription.id,
                        authToken: token,
                        unreadOnly: false,
                        limit: 1_000,
                        continuation: continuation
                    )
                    for item in page.items { try upsert(item: item, feed: feed, in: context) }
                    continuation = page.continuation
                    pages += 1
                } while pages < 20 && continuation.map({ !$0.isEmpty }) == true
                feed.lastFetchedAt = .now
            }
            account.lastSyncAt = .now
            account.lastSyncError = nil
            try context.save()
            _ = try ArticleQueueService().ensureCurrent(in: context)
        } catch {
            account.lastSyncError = error.localizedDescription
            try? context.save()
            throw error
        }
    }

    func enqueueMutation(for article: Article, transition: ArticleState, in context: ModelContext) {
        guard let remoteID = article.remoteID else { return }
        let kind: FreshRSSMutationKind?
        switch transition {
        case .read: kind = .markRead
        case .saved: kind = .star
        case .queued: kind = .unstar
        default: kind = nil
        }
        guard let kind else { return }
        context.insert(PendingSyncMutation(remoteArticleID: remoteID, kind: kind))
        try? context.save()
    }

    private func upsert(subscription: FreshRSSSubscription, in context: ModelContext) throws -> Feed {
        let remoteID = subscription.id
        if let feed = try context.fetch(FetchDescriptor<Feed>(predicate: #Predicate { $0.remoteID == remoteID })).first {
            feed.title = subscription.title
            feed.websiteURL = subscription.htmlURL
            if let feedURL = subscription.resolvedFeedURL { feed.feedURL = feedURL }
            feed.folderName = subscription.folderName
            return feed
        }
        guard let feedURL = subscription.resolvedFeedURL else { throw FreshRSSSyncError.invalidSubscriptionURL }
        let feed = Feed(
            title: subscription.title,
            websiteURL: subscription.htmlURL,
            feedURL: feedURL,
            remoteID: subscription.id,
            folderName: subscription.folderName
        )
        context.insert(feed)
        return feed
    }

    private func upsert(item: FreshRSSItem, feed: Feed, in context: ModelContext) throws {
        let snapshot = item.snapshot
        let remoteID = snapshot.remoteID
        let existing = try context.fetch(FetchDescriptor<Article>(predicate: #Predicate { $0.remoteID == remoteID })).first
        let article = existing ?? Article(guid: snapshot.guid, title: snapshot.title, feed: feed)
        if existing == nil { context.insert(article) }
        article.guid = snapshot.guid
        article.title = snapshot.title
        article.url = snapshot.url
        article.author = snapshot.author
        article.publishedAt = snapshot.publishedAt ?? article.publishedAt
        article.summary = snapshot.summary
        article.contentHTML = snapshot.contentHTML
        article.estimatedReadingMinutes = Self.readingMinutes(for: snapshot.contentHTML ?? snapshot.summary)
        article.remoteID = snapshot.remoteID
        article.isRemoteStarred = snapshot.isStarred
        article.feed = feed
        if article.state != .skipped && article.state != .current {
            article.state = snapshot.isStarred ? .saved : snapshot.isRead ? .read : .queued
        }
    }

    private func flushMutations(client: any FreshRSSAPI, token: String, in context: ModelContext) async throws {
        var descriptor = FetchDescriptor<PendingSyncMutation>(sortBy: [SortDescriptor(\.createdAt)])
        descriptor.fetchLimit = 250
        for mutation in try context.fetch(descriptor) {
            mutation.attempts += 1
            // Persist the attempt before crossing the network boundary. If
            // the process is suspended or the request fails, a later sync can
            // show/retry the durable mutation instead of losing it.
            try context.save()
            do {
                switch mutation.kind {
                case .markRead: try await client.markRead(itemID: mutation.remoteArticleID, authToken: token)
                case .markUnread: try await client.markUnread(itemID: mutation.remoteArticleID, authToken: token)
                case .star: try await client.setStarred(itemID: mutation.remoteArticleID, authToken: token, starred: true)
                case .unstar: try await client.setStarred(itemID: mutation.remoteArticleID, authToken: token, starred: false)
                case nil: break
                }
            } catch {
                // Keep the mutation and its attempt count. Do not continue
                // with later mutations: ordering matters for opposite
                // operations on the same remote item.
                try? context.save()
                throw error
            }
            context.delete(mutation)
            try context.save()
        }
    }

    private static func readingMinutes(for html: String?) -> Int {
        let plain = (html ?? "").replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return max(1, Int(ceil(Double(plain.split(whereSeparator: \.isWhitespace).count) / 220)))
    }
}

extension FreshRSSSyncService: FreshRSSSyncing {}

enum FreshRSSSyncError: LocalizedError {
    case missingCredentials
    case invalidSubscriptionURL

    var errorDescription: String? {
        switch self {
        case .missingCredentials: "FreshRSS credentials are missing. Reconnect your account."
        case .invalidSubscriptionURL: "FreshRSS returned an invalid subscription address."
        }
    }
}

extension FreshRSSError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidServerURL: "Enter a valid FreshRSS server address."
        case .invalidCredentials, .missingAuthToken: "FreshRSS rejected those credentials. Use an API password from your FreshRSS profile."
        case .invalidResponse: "FreshRSS returned an unexpected response."
        case .httpStatus(let status, _): "FreshRSS returned HTTP \(status)."
        case .decodingFailed: "FreshRSS returned data OneFeed could not read."
        case .unsupportedMutation: "That FreshRSS action is not supported."
        }
    }
}
