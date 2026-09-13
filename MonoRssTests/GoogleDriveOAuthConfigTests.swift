import Foundation
import Testing
@testable import OneFeed

struct GoogleDriveOAuthConfigTests {
    @Test func reversedClientIDMapsGoogleIosClient() {
        #expect(
            GoogleDriveOAuthConfig.reversedClientID(from: "123-abc.apps.googleusercontent.com")
                == "com.googleusercontent.apps.123-abc"
        )
        #expect(
            GoogleDriveOAuthConfig.reversedClientID(from: "123-abc.apps.googleusercontent.com") + ":/oauth2redirect"
                == "com.googleusercontent.apps.123-abc:/oauth2redirect"
        )
    }

    @Test func isConfiguredFalseForEmptyAndReplace() {
        #expect(GoogleDriveOAuthConfig.isConfiguredClientID("") == false)
        #expect(GoogleDriveOAuthConfig.isConfiguredClientID("   ") == false)
        #expect(GoogleDriveOAuthConfig.isConfiguredClientID("REPLACE.apps.googleusercontent.com") == false)
        #expect(GoogleDriveOAuthConfig.isConfiguredClientID("123-REPLACE-abc.apps.googleusercontent.com") == false)
        #expect(GoogleDriveOAuthConfig.isConfiguredClientID("123-abc") == false)
        #expect(GoogleDriveOAuthConfig.isConfiguredClientID("123-abc.apps.googleusercontent.com") == true)
        #expect(
            GoogleDriveOAuthConfig.isConfiguredClientID(
                "000000000000-abcdefghijklmnopqrstuvwxyz123456.apps.googleusercontent.com"
            ) == true
        )
        #expect(
            GoogleDriveOAuthConfig.reversedClientID(
                from: "000000000000-abcdefghijklmnopqrstuvwxyz123456.apps.googleusercontent.com"
            ) == "com.googleusercontent.apps.000000000000-abcdefghijklmnopqrstuvwxyz123456"
        )
    }

    @Test func backupFileNameMatchesLibraryDocument() {
        #expect(GoogleDriveOAuthConfig.backupFileName == LibraryDocumentFormat.fileName)
        #expect(GoogleDriveOAuthConfig.backupFileName == "OneFeed.library.json")
    }
}
