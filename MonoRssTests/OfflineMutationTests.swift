import Foundation
import Testing
@testable import MonoRss

private actor RecordingMutationAPI: FreshRSSAPI {
    enum Failure: Error, Equatable { case unavailable }

    private(set) var calls: [(String, FreshRSSMutationKind)] = []
    var shouldFail = false

    func login(credentials: FreshRSSCredentials) async throws -> FreshRSSAuthResponse {
        FreshRSSAuthResponse(authToken: "token", userName: credentials.username)
    }

    func subscriptions(authToken: String) async throws -> FreshRSSSubscriptionResponse {
        FreshRSSSubscriptionResponse(subscriptions: [])
    }

    func itemIDs(streamID: String, authToken: String, unreadOnly: Bool, limit: Int, continuation: String?) async throws -> FreshRSSStreamItemIDsResponse {
        FreshRSSStreamItemIDsResponse(itemRefs: [])
    }

    func itemContents(itemIDs: [String], authToken: String) async throws -> FreshRSSStreamContentsResponse {
        FreshRSSStreamContentsResponse(items: [])
    }

    func streamContents(streamID: String, authToken: String, unreadOnly: Bool, limit: Int, continuation: String?) async throws -> FreshRSSStreamContentsResponse {
        FreshRSSStreamContentsResponse(items: [])
    }

    func markRead(itemID: String, authToken: String) async throws {
        try record(itemID: itemID, kind: .markRead)
    }

    func markUnread(itemID: String, authToken: String) async throws {
        try record(itemID: itemID, kind: .markUnread)
    }

    func setStarred(itemID: String, authToken: String, starred: Bool) async throws {
        try record(itemID: itemID, kind: starred ? .star : .unstar)
    }

    func setReadLater(itemID: String, authToken: String, readLater: Bool) async throws {}
    func quickAdd(url: String, authToken: String) async throws -> FreshRSSQuickAddResponse {
        FreshRSSQuickAddResponse(numResults: 1, query: url, streamID: "feed/1", streamName: url)
    }
    func unsubscribe(streamID: String, authToken: String) async throws {}

    private func record(itemID: String, kind: FreshRSSMutationKind) throws {
        calls.append((itemID, kind))
        if shouldFail { throw Failure.unavailable }
    }

    func recordedCalls() -> [(String, FreshRSSMutationKind)] { calls }
}

@MainActor
struct OfflineMutationTests {
    @Test func successfulFlushRemovesDurableMutations() async throws {
        let api = RecordingMutationAPI()
        let store = InMemoryFreshRSSMutationStore()
        let service = FreshRSSMutationService(api: api, store: store)
        try await service.enqueue(itemID: "remote-1", kind: .markRead)
        try await service.enqueue(itemID: "remote-2", kind: .star)

        let applied = try await service.flush(authToken: "token")
        #expect(applied == 2)
        let pending = await store.pending(limit: 10)
        #expect(pending.isEmpty)
        let calls = await api.recordedCalls()
        #expect(calls.map(\.1) == [.markRead, .star])
    }

    @Test func failedFlushRetainsMutationAndIncrementsAttempt() async throws {
        let api = RecordingMutationAPI()
        await api.setShouldFail(true)
        let store = InMemoryFreshRSSMutationStore()
        let service = FreshRSSMutationService(api: api, store: store)
        try await service.enqueue(itemID: "remote-1", kind: .markUnread)

        await #expect(throws: RecordingMutationAPI.Failure.unavailable) {
            try await service.flush(authToken: "token")
        }
        let pending = await store.pending(limit: 10)
        #expect(pending.count == 1)
        #expect(pending[0].attempts == 1)
        #expect(pending[0].itemID == "remote-1")
    }

    @Test func mutationModelRoundTripsKindForOfflinePersistence() throws {
        let mutation = PendingFreshRSSMutation(itemID: "remote-1", kind: .star)
        #expect(mutation.kind == .star)
        #expect(mutation.attempts == 0)
    }
}

private extension RecordingMutationAPI {
    func setShouldFail(_ value: Bool) {
        shouldFail = value
    }
}
