import Foundation
import Testing
@testable import OneFeed

struct CloudFileReconcilerTests {
    @Test func equalHashesAreInSync() {
        let decision = CloudFileReconciler.decide(
            localHash: "aaa",
            remoteHash: "aaa",
            lastSyncedHash: "bbb"
        )
        #expect(decision == .inSync)
    }

    @Test func remoteMatchesLastSyncedAndLocalDiffersPushes() {
        let decision = CloudFileReconciler.decide(
            localHash: "local-new",
            remoteHash: "synced",
            lastSyncedHash: "synced"
        )
        #expect(decision == .push)
    }

    @Test func localMatchesLastSyncedAndRemoteDiffersPulls() {
        let decision = CloudFileReconciler.decide(
            localHash: "synced",
            remoteHash: "remote-new",
            lastSyncedHash: "synced"
        )
        #expect(decision == .pull)
    }

    @Test func bothSidesDifferFromLastSyncedConflicts() {
        let decision = CloudFileReconciler.decide(
            localHash: "local-new",
            remoteHash: "remote-new",
            lastSyncedHash: "synced"
        )
        #expect(decision == .conflict)
    }

    @Test func nilRemoteHashPushes() {
        let decision = CloudFileReconciler.decide(
            localHash: "local",
            remoteHash: nil,
            lastSyncedHash: "synced"
        )
        #expect(decision == .push)
    }

    @Test func emptyRemoteHashPushes() {
        let decision = CloudFileReconciler.decide(
            localHash: "local",
            remoteHash: "",
            lastSyncedHash: "synced"
        )
        #expect(decision == .push)
    }

    @Test func nilLastSyncedAndDifferentHashesConflict() {
        let decision = CloudFileReconciler.decide(
            localHash: "local",
            remoteHash: "remote",
            lastSyncedHash: nil
        )
        #expect(decision == .conflict)
    }

    @Test func nilLastSyncedAndEqualHashesAreInSync() {
        let decision = CloudFileReconciler.decide(
            localHash: "same",
            remoteHash: "same",
            lastSyncedHash: nil
        )
        #expect(decision == .inSync)
    }
}
