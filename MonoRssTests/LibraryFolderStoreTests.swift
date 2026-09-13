import Foundation
import Testing
@testable import OneFeed

@MainActor
struct LibraryFolderStoreTests {
    @Test func displayNameDetectsICloudAndGoogleDrive() {
        let iCloud = URL(fileURLWithPath: "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/OneFeed")
        #expect(LibraryFolderStore.displayName(for: iCloud) == "iCloud Drive")
        let drive = URL(fileURLWithPath: "/Users/me/Library/CloudStorage/GoogleDrive-me/My Drive/OneFeed")
        #expect(LibraryFolderStore.displayName(for: drive) == "Google Drive")
        let local = URL(fileURLWithPath: "/Users/me/Documents/Reading")
        #expect(LibraryFolderStore.displayName(for: local) == "Reading")
    }

    @Test func conflictCopiesAreIgnored() {
        let good = URL(fileURLWithPath: "/tmp/OneFeed.library.json")
        let conflict = URL(fileURLWithPath: "/tmp/OneFeed.library (conflicted copy).json")
        #expect(!LibraryFolderStore.isConflictCopy(good))
        #expect(LibraryFolderStore.isConflictCopy(conflict))
    }

    @Test func libraryFileURLAppendsDefaultNameForFolders() {
        let folder = URL(fileURLWithPath: "/tmp/OneFeed", isDirectory: true)
        let file = LibraryFolderStore.libraryFileURL(from: folder, isFile: false)
        #expect(file.lastPathComponent == "OneFeed.library.json")
        let existing = URL(fileURLWithPath: "/tmp/custom.json")
        #expect(LibraryFolderStore.libraryFileURL(from: existing, isFile: true) == existing)
    }
}
