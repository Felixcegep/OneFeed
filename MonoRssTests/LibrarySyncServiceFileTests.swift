import Foundation
import SwiftData
import Testing
@testable import OneFeed

@Suite(.serialized)
@MainActor
struct LibrarySyncServiceFileTests {
    @Test func syncWhileReadingLeavesTheFileUntilTheStoryCloses() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent(LibraryDocumentFormat.fileName)
        defer {
            LibraryFolderStore.clear()
            try? FileManager.default.removeItem(at: root)
        }

        try remoteLibrary(title: "Remote Source", url: "https://remote.test/rss").write(to: file, options: .atomic)
        let suiteName = "LibrarySyncServiceFileTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = LibrarySyncService(defaults: defaults)
        let context = try InMemoryStore.makeContext()
        service.configure(with: context)
        service.hasActiveReadingSession = true
        await service.attach(url: file)

        let later = try remoteLibrary(title: "Later Source", url: "https://later.test/rss")
        try later.write(to: file, options: .atomic)
        await service.syncNow()

        let during = try context.fetch(FetchDescriptor<Feed>()).map(\.title)
        #expect(during.contains("Later Source") == false)
        #expect(try Data(contentsOf: file) == later)

        service.hasActiveReadingSession = false
        var titles: [String] = []
        for _ in 0..<40 {
            titles = try context.fetch(FetchDescriptor<Feed>()).map(\.title)
            if titles.contains("Later Source") { break }
            await Task.yield()
        }
        #expect(titles.contains("Later Source"))
    }

    private func remoteLibrary(title: String, url: String) throws -> Data {
        let document = LibraryDocument(
            schemaVersion: LibraryDocumentFormat.schemaVersion,
            updatedAt: Date(timeIntervalSince1970: 50),
            folderNames: [],
            feeds: [
                LibraryFeed(
                    feedURL: url,
                    title: title,
                    websiteURL: nil,
                    isEnabled: true,
                    contentKind: "article",
                    includeInToday: true,
                    includeVideos: true,
                    includeShorts: false,
                    minVideoSeconds: 180,
                    blockedWords: "",
                    updatedAt: Date(timeIntervalSince1970: 40)
                )
            ],
            articles: [],
            tombstones: [],
            currentArticleKey: nil,
            currentUpdatedAt: nil
        )
        return try document.encoded()
    }
}
