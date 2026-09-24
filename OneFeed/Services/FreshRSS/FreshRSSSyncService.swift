import Foundation
import SwiftData

@MainActor
protocol FreshRSSSyncing: AnyObject {
    func connect(serverURL: URL, username: String, password: String, in context: ModelContext) async throws -> SyncAccount
    func disconnect(account: SyncAccount, in context: ModelContext) async throws
    func sync(account: SyncAccount, in context: ModelContext, progress: RefreshProgress?) async throws
    func enqueueMutation(for article: Article, transition: ArticleState, in context: ModelContext)
    func addSubscription(from input: String, folderName: String?, in context: ModelContext) async throws -> Feed
    func removeSubscription(_ feed: Feed, in context: ModelContext) async throws
    func subscribeLocalFeeds(in context: ModelContext) async throws
}

extension FreshRSSSyncing {
    func sync(account: SyncAccount, in context: ModelContext) async throws {
        try await sync(account: account, in: context, progress: nil)
    }

    func addSubscription(from input: String, in context: ModelContext) async throws -> Feed {
        try await addSubscription(from: input, folderName: nil, in: context)
    }
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
        try await sync(account: account, in: context, progress: nil)
        try await subscribeLocalFeeds(in: context)
        return account
    }

    func disconnect(account: SyncAccount, in context: ModelContext) async throws {
        try await credentialStore.delete(for: account.id)
        let remoteFeeds = try context.fetch(FetchDescriptor<Feed>(predicate: #Predicate { $0.remoteID != nil }))
        for feed in remoteFeeds { feed.remoteID = nil }
        context.delete(account)
        _ = try ArticleIdentity.mergeDuplicates(in: context)
        try context.save()
    }

    func sync(account: SyncAccount, in context: ModelContext, progress: RefreshProgress? = nil) async throws {
        guard account.provider == .freshRSS, let serverURL = account.serverURL, let username = account.username,
              let credentials = try await credentialStore.load(for: account.id) else {
            throw FreshRSSSyncError.missingCredentials
        }
        let accountID = account.id
        let configuration = try FreshRSSConfiguration(baseURL: serverURL, username: username)
        let client = clientFactory(configuration)
        do {
            let token = try await client.login(credentials: credentials).authToken
            let actor = try SwiftDataIngest.actor(from: context)
            try await actor.syncFreshRSS(
                accountID: accountID,
                client: client,
                token: token,
                progress: RefreshProgressSink(progress)
            )
            _ = try? ArticleQueueService().ensureCurrent(in: context)
        } catch {
            try? await SwiftDataIngest.actor(from: context).setFreshRSSSyncError(
                accountID: accountID,
                message: error.localizedDescription
            )
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

    /// Drops mutations for `remoteID` that were not already pending. Rows in `ids` stay.
    func cancelPendingMutations(forRemoteID remoteID: String, keeping ids: Set<UUID>, in context: ModelContext) {
        let remoteID = remoteID
        let descriptor = FetchDescriptor<PendingSyncMutation>(
            predicate: #Predicate { $0.remoteArticleID == remoteID }
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        var removed = false
        for row in rows where !ids.contains(row.id) {
            context.delete(row)
            removed = true
        }
        if removed { try? context.save() }
    }

    /// Queues a local markUnread. No network call.
    func enqueueCompensatingUnread(for article: Article, in context: ModelContext) {
        guard let remoteID = article.remoteID else { return }
        context.insert(PendingSyncMutation(remoteArticleID: remoteID, kind: .markUnread))
        try? context.save()
    }

    func addSubscription(from input: String, folderName: String? = nil, in context: ModelContext) async throws -> Feed {
        guard let account = try enabledAccount(in: context) else { throw FreshRSSSyncError.missingCredentials }
        guard let url = FeedService.normalizedURL(from: input) else { throw FeedServiceError.invalidAddress }
        let (client, token) = try await authorizedClient(for: account)
        _ = try await client.quickAdd(url: url.absoluteString, authToken: token)
        try await sync(account: account, in: context)
        let feeds = try context.fetch(FetchDescriptor<Feed>())
        if let match = feeds.first(where: { $0.feedURL.absoluteString == url.absoluteString }) {
            let normalized = folderName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let folder = normalized, !folder.isEmpty, match.addFolder(folder) {
                LibraryChange.note(match)
                try context.save()
            }
            return match
        }
        throw FreshRSSSyncError.invalidSubscriptionURL
    }

    func removeSubscription(_ feed: Feed, in context: ModelContext) async throws {
        if let remoteID = feed.remoteID, let account = try enabledAccount(in: context) {
            let (client, token) = try await authorizedClient(for: account)
            try await client.unsubscribe(streamID: remoteID, authToken: token)
        }
        LibraryChange.noteRemovedFeed(feed)
        context.delete(feed)
        try context.save()
    }

    func subscribeLocalFeeds(in context: ModelContext) async throws {
        guard let account = try enabledAccount(in: context) else { return }
        let (client, token) = try await authorizedClient(for: account)
        let locals = try context.fetch(FetchDescriptor<Feed>(predicate: #Predicate { $0.remoteID == nil }))
        let subscriptions = locals.filter(\.refreshesOverRSS)
        for feed in subscriptions {
            _ = try await client.quickAdd(url: feed.feedURL.absoluteString, authToken: token)
        }
        if !subscriptions.isEmpty {
            try await sync(account: account, in: context, progress: nil)
        }
    }

    private func enabledAccount(in context: ModelContext) throws -> SyncAccount? {
        let freshRSS = SyncProvider.freshRSS.rawValue
        return try context.fetch(FetchDescriptor<SyncAccount>(predicate: #Predicate { $0.providerRawValue == freshRSS })).first(where: \.isEnabled)
    }

    private func authorizedClient(for account: SyncAccount) async throws -> (any FreshRSSAPI, String) {
        guard let serverURL = account.serverURL, let username = account.username,
              let credentials = try await credentialStore.load(for: account.id) else {
            throw FreshRSSSyncError.missingCredentials
        }
        let configuration = try FreshRSSConfiguration(baseURL: serverURL, username: username)
        let client = clientFactory(configuration)
        let token = try await client.login(credentials: credentials).authToken
        return (client, token)
    }

}

extension LibraryIngestActor {
    func syncFreshRSS(
        accountID: UUID,
        client: any FreshRSSAPI,
        token: String,
        progress: RefreshProgressSink
    ) async throws {
        modelContext.autosaveEnabled = false
        guard let ingestAccount = try modelContext.fetch(FetchDescriptor<SyncAccount>(predicate: #Predicate { $0.id == accountID })).first else {
            throw FreshRSSSyncError.missingCredentials
        }
        try await flushMutations(client: client, token: token)
        let subscriptions = try await client.subscriptions(authToken: token).subscriptions
        await progress.begin(phase: .sync, total: subscriptions.count)
        var index = ArticleIdentityIndex(articles: identityArticles())
        let existingFeeds = try modelContext.fetch(FetchDescriptor<Feed>())
        var feedsByRemoteID: [String: Feed] = [:]
        var feedsByURL: [String: Feed] = [:]
        feedsByRemoteID.reserveCapacity(existingFeeds.count)
        feedsByURL.reserveCapacity(existingFeeds.count)
        for feed in existingFeeds {
            if let remoteID = feed.remoteID { feedsByRemoteID[remoteID] = feed }
            feedsByURL[ArticleIdentity.feedKey(feed.feedURL)] = feed
        }
        var processed = 0
        for subscription in subscriptions {
            if FeedSeedCatalog.isRetired(title: subscription.title, url: subscription.resolvedFeedURL) {
                await progress.finishItem(newArticles: 0)
                continue
            }
            let feed = try upsertSubscription(
                subscription,
                feedsByRemoteID: &feedsByRemoteID,
                feedsByURL: &feedsByURL
            )
            var continuation: String?
            var pages = 0
            var added = 0
            repeat {
                let page = try await client.streamContents(
                    streamID: subscription.id,
                    authToken: token,
                    unreadOnly: false,
                    limit: 1_000,
                    continuation: continuation
                )
                for (offset, item) in page.items.enumerated() {
                    if upsertItem(item, feed: feed, index: &index) { added += 1 }
                    if offset % 32 == 31 {
                        await Task.yield()
                    }
                }
                continuation = page.continuation
                pages += 1
            } while pages < 20 && continuation.map({ !$0.isEmpty }) == true
            feed.lastFetchedAt = .now
            await progress.finishItem(newArticles: added)
            processed += 1
            if processed.isMultiple(of: 2) {
                await Task.yield()
            }
        }
        _ = try ArticleIdentity.mergeDuplicates(in: modelContext, persist: false)
        ingestAccount.lastSyncAt = .now
        ingestAccount.lastSyncError = nil
        try persistIfNeeded()
    }

    private func upsertSubscription(
        _ subscription: FreshRSSSubscription,
        feedsByRemoteID: inout [String: Feed],
        feedsByURL: inout [String: Feed]
    ) throws -> Feed {
        let remoteID = subscription.id
        if let feed = feedsByRemoteID[remoteID] {
            applySubscription(subscription, to: feed)
            return feed
        }
        guard let feedURL = subscription.resolvedFeedURL else { throw FreshRSSSyncError.invalidSubscriptionURL }
        let key = ArticleIdentity.feedKey(feedURL)
        if let existing = feedsByURL[key] {
            existing.remoteID = remoteID
            applySubscription(subscription, to: existing)
            feedsByRemoteID[remoteID] = existing
            return existing
        }
        let feed = Feed(
            title: subscription.title,
            websiteURL: subscription.htmlURL,
            feedURL: feedURL,
            remoteID: subscription.id,
            folderName: subscription.folderName,
            contentKind: subscription.contentType ?? "article"
        )
        modelContext.insert(feed)
        feedsByRemoteID[remoteID] = feed
        feedsByURL[key] = feed
        return feed
    }

    private func applySubscription(_ subscription: FreshRSSSubscription, to feed: Feed) {
        feed.title = subscription.title
        feed.websiteURL = subscription.htmlURL
        if let feedURL = subscription.resolvedFeedURL { feed.feedURL = feedURL }
        feed.applyRemotePrimaryFolder(subscription.folderName)
        if let kind = subscription.contentType { feed.contentKind = kind }
    }

    private func upsertItem(_ item: FreshRSSItem, feed: Feed, index: inout ArticleIdentityIndex) -> Bool {
        let snapshot = item.snapshot
        let existing = index.existing(
            url: snapshot.url,
            guid: snapshot.guid,
            feedID: feed.id,
            remoteID: snapshot.remoteID,
            videoID: YouTubeProcessor.parseVideoID(from: snapshot.url)
                ?? YouTubeProcessor.parseVideoID(fromGUID: snapshot.guid)
        )
        let article = existing ?? Article(guid: snapshot.guid, title: snapshot.title, feed: feed)
        let isNew = existing == nil
        if isNew { modelContext.insert(article) }
        article.guid = snapshot.guid
        article.title = snapshot.title
        article.url = snapshot.url
        article.author = snapshot.author
        article.publishedAt = snapshot.publishedAt ?? article.publishedAt
        article.summary = snapshot.summary
        if let remoteHTML = snapshot.contentHTML {
            let existingHTML = article.contentHTML ?? ""
            if remoteHTML.count >= existingHTML.count {
                article.contentHTML = remoteHTML
            }
        }
        if let minutes = snapshot.consumeMinutes, minutes > 0 {
            article.estimatedReadingMinutes = max(article.estimatedReadingMinutes, minutes)
        } else if isNew {
            article.estimatedReadingMinutes = max(
                1,
                ContentClassifier.readingMinutes(
                    words: ContentClassifier.wordCount(in: snapshot.contentHTML ?? snapshot.summary ?? "")
                )
            )
        }
        article.remoteID = snapshot.remoteID
        article.isRemoteStarred = snapshot.isStarred
        article.contentKind = snapshot.contentKind
        article.durationSeconds = snapshot.durationSeconds ?? 0
        article.feed = feed
        if article.state != .skipped && article.state != .current {
            article.state = snapshot.isStarred ? .saved : snapshot.isRead ? .read : .queued
        }
        index.register(article)
        return isNew
    }

    private func flushMutations(client: any FreshRSSAPI, token: String) async throws {
        var descriptor = FetchDescriptor<PendingSyncMutation>(sortBy: [SortDescriptor(\.createdAt)])
        descriptor.fetchLimit = 250
        for mutation in try modelContext.fetch(descriptor) {
            mutation.attempts += 1
            do {
                switch mutation.kind {
                case .markRead: try await client.markRead(itemID: mutation.remoteArticleID, authToken: token)
                case .markUnread: try await client.markUnread(itemID: mutation.remoteArticleID, authToken: token)
                case .star: try await client.setStarred(itemID: mutation.remoteArticleID, authToken: token, starred: true)
                case .unstar:
                    try await client.setStarred(itemID: mutation.remoteArticleID, authToken: token, starred: false)
                    try await client.setReadLater(itemID: mutation.remoteArticleID, authToken: token, readLater: false)
                case nil: break
                }
            } catch {
                try? persistIfNeeded()
                throw error
            }
            modelContext.delete(mutation)
        }
        try persistIfNeeded()
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
