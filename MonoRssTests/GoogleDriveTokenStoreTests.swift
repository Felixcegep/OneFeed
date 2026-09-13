import Foundation
import Testing
@testable import OneFeed

struct GoogleDriveTokenStoreTests {
    @Test func saveLoadAndDeleteRoundTrip() throws {
        let store = GoogleDriveTokenStore(
            service: "felix.MonoRss.googleDriveOAuth.tests.\(UUID().uuidString)",
            account: "credentials"
        )
        store.delete()
        defer { store.delete() }

        #expect(store.load() == nil)
        let credentials = GoogleDriveCredentials(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            tokenType: "Bearer",
            accountEmail: "user@example.com"
        )
        try store.save(credentials)
        #expect(store.load() == credentials)
        store.delete()
        #expect(store.load() == nil)
    }
}
