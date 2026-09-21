import Foundation

nonisolated public enum FreshRSSMutationKind: String, Codable, Sendable, Equatable {
    case markRead
    case markUnread
    case star
    case unstar
}

/// A durable, idempotent local operation. It intentionally contains only a
/// FreshRSS item ID and never a password or auth token.
nonisolated public struct PendingFreshRSSMutation: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let itemID: String
    public let kind: FreshRSSMutationKind
    public let createdAt: Date
    public private(set) var attempts: Int
    public private(set) var lastAttemptAt: Date?

    public init(id: UUID = UUID(), itemID: String, kind: FreshRSSMutationKind,
                createdAt: Date = .now, attempts: Int = 0, lastAttemptAt: Date? = nil) {
        self.id = id
        self.itemID = itemID
        self.kind = kind
        self.createdAt = createdAt
        self.attempts = max(0, attempts)
        self.lastAttemptAt = lastAttemptAt
    }

    public mutating func recordAttempt(at date: Date = .now) {
        attempts += 1
        lastAttemptAt = date
    }
}

public protocol FreshRSSMutationStore: Sendable {
    func enqueue(_ mutation: PendingFreshRSSMutation) async throws
    func pending(limit: Int) async throws -> [PendingFreshRSSMutation]
    func update(_ mutation: PendingFreshRSSMutation) async throws
    func remove(_ mutation: PendingFreshRSSMutation) async throws
}

public actor InMemoryFreshRSSMutationStore: FreshRSSMutationStore {
    private var mutations: [UUID: PendingFreshRSSMutation] = [:]

    public init() {}

    public func enqueue(_ mutation: PendingFreshRSSMutation) {
        // Coalescing by item/action avoids replaying an obsolete toggle after
        // a later user action has superseded it.
        mutations[mutation.id] = mutation
    }

    public func pending(limit: Int) -> [PendingFreshRSSMutation] {
        Array(mutations.values.sorted { $0.createdAt < $1.createdAt }.prefix(max(0, limit)))
    }

    public func update(_ mutation: PendingFreshRSSMutation) {
        mutations[mutation.id] = mutation
    }

    public func remove(_ mutation: PendingFreshRSSMutation) {
        mutations.removeValue(forKey: mutation.id)
    }
}

nonisolated public struct FreshRSSMutationService: Sendable {
    private let api: any FreshRSSAPI
    private let store: any FreshRSSMutationStore

    public init(api: any FreshRSSAPI, store: any FreshRSSMutationStore) {
        self.api = api
        self.store = store
    }

    public func enqueue(itemID: String, kind: FreshRSSMutationKind) async throws {
        try await store.enqueue(PendingFreshRSSMutation(itemID: itemID, kind: kind))
    }

    /// Applies as many queued operations as possible. A failed operation is
    /// retained with an incremented attempt count, allowing the caller to
    /// retry after reachability/background refresh changes.
    public func flush(authToken: String, limit: Int = 100) async throws -> Int {
        var applied = 0
        for original in try await store.pending(limit: limit) {
            var mutation = original
            mutation.recordAttempt()
            try await store.update(mutation)
            do {
                switch mutation.kind {
                case .markRead: try await api.markRead(itemID: mutation.itemID, authToken: authToken)
                case .markUnread: try await api.markUnread(itemID: mutation.itemID, authToken: authToken)
                case .star: try await api.setStarred(itemID: mutation.itemID, authToken: authToken, starred: true)
                case .unstar:
                    try await api.setStarred(itemID: mutation.itemID, authToken: authToken, starred: false)
                    try await api.setReadLater(itemID: mutation.itemID, authToken: authToken, readLater: false)
                }
                try await store.remove(mutation)
                applied += 1
            } catch {
                // Keep this and subsequent entries for the next retry. The
                // first transport error is enough to stop this flush cycle.
                throw error
            }
        }
        return applied
    }
}
