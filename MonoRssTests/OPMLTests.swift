import Foundation
import SwiftData
import Testing
@testable import OneFeed

@MainActor
struct OPMLTests {
    private func context() throws -> ModelContext {
        try InMemoryStore.makeContext()
    }

    @Test func importPreservesFolderHierarchyAndSkipsDuplicateURLs() throws {
        let context = try context()
        let opml = """
        <?xml version="1.0"?><opml version="2.0"><body>
          <outline text="Must read">
            <outline text="One" xmlUrl="https://one.test/rss" />
            <outline title="Two" xmlUrl="https://two.test/feed" />
          </outline>
          <outline text="Builders">
            <outline text="Three" xmlUrl="https://three.test/atom" />
          </outline>
          <outline text="Duplicate" xmlUrl="https://one.test/rss" />
          <outline text="Loose" xmlUrl="https://loose.test/rss" />
        </body></opml>
        """

        let inserted = try OPMLService().importDocument(Data(opml.utf8), in: context)
        #expect(inserted == 4)
        let feeds = try context.fetch(FetchDescriptor<Feed>(sortBy: [SortDescriptor(\.title)]))
        #expect(feeds.map(\.title) == ["Loose", "One", "Three", "Two"])
        #expect(feeds.first { $0.title == "One" }?.folderName == "Must read")
        #expect(feeds.first { $0.title == "Two" }?.folderName == "Must read")
        #expect(feeds.first { $0.title == "Three" }?.folderName == "Builders")
        #expect(feeds.first { $0.title == "Loose" }?.folderName == nil)
    }

    @Test func importUnionsSameURLUnderTwoFolders() throws {
        let context = try context()
        let opml = """
        <?xml version="1.0"?><opml version="2.0"><body>
          <outline text="Must read">
            <outline text="One" xmlUrl="https://one.test/rss" />
          </outline>
          <outline text="Philosophy">
            <outline text="One again" xmlUrl="https://one.test/rss" />
          </outline>
        </body></opml>
        """

        let inserted = try OPMLService().importDocument(Data(opml.utf8), in: context)
        #expect(inserted == 1)
        let feeds = try context.fetch(FetchDescriptor<Feed>())
        #expect(feeds.count == 1)
        let feed = try #require(feeds.first)
        #expect(feed.memberships.contains("Must read"))
        #expect(feed.memberships.contains("Philosophy"))
        #expect(feed.folderName == "Must read")
    }

    @Test func exportGroupsFeedsByFolder() throws {
        let context = try context()
        let must = Feed(title: "A & B", feedURL: URL(string: "https://example.test/a?x=1&y=2")!, folderName: "Must read")
        let loose = Feed(title: "Loose", feedURL: URL(string: "https://loose.test/rss")!)
        context.insert(must)
        context.insert(loose)

        let document = OPMLService().exportDocument(feeds: [must, loose])
        let xml = String(decoding: document.data, as: UTF8.self)
        #expect(xml.contains("A &amp; B"))
        #expect(xml.contains("x=1&amp;y=2"))
        #expect(xml.contains("<outline text=\"Must read\""))
        #expect(xml.contains("xmlUrl=\"https://example.test/a?x=1&amp;y=2\""))
        #expect(xml.contains("xmlUrl=\"https://loose.test/rss\""))
    }

    @Test func curatedPackOPMLRoundTripsFolders() throws {
        let context = try context()
        let document = FeedSeedCatalog.opmlDocument()
        let inserted = try OPMLService().importDocument(document.data, in: context)
        #expect(inserted == FeedSeedCatalog.feeds.count)
        #expect(FeedSeedCatalog.feeds.count == 60)
        let folders = Set((try context.fetch(FetchDescriptor<Feed>())).compactMap(\.folderName))
        #expect(folders == Set(FeedSeedCatalog.folderOrder))
    }

    @Test func opmlParseRunsOffTheMainActor() async throws {
        let opml = """
        <?xml version="1.0"?><opml version="2.0"><body>
          <outline text="Must read">
            <outline text="One" xmlUrl="https://one.test/rss" />
          </outline>
        </body></opml>
        """
        let parsed = try await Task.detached {
            try OPMLService.parse(Data(opml.utf8))
        }.value
        #expect(parsed.count == 1)
        #expect(parsed.first?.title == "One")
        #expect(parsed.first?.folderName == "Must read")
    }

    @Test func previewMatchesSourcesAwayFromTheOpenScreen() throws {
        let context = try context()
        context.insert(Feed(title: "One", feedURL: URL(string: "https://one.test/rss")!, folderName: "Must read"))
        try context.save()
        let outlines = [
            OPMLFeedOutline(title: "One", feedURL: URL(string: "https://one.test/rss")!, folderName: "Philosophy"),
            OPMLFeedOutline(title: "New", feedURL: URL(string: "https://new.test/rss")!, folderName: nil)
        ]
        let preview = try OPMLService.preview(outlines, in: context.container)
        #expect(preview.newSourceCount == 1)
        #expect(preview.alreadyPresentCount == 1)
        #expect(preview.folderMembershipsToAdd == 1)
        #expect(try context.fetch(FetchDescriptor<Feed>()).count == 1)
    }

    @Test func confirmingOPMLImportWritesSourcesOnTheIngestActor() async throws {
        let context = try context()
        let outlines = [
            OPMLFeedOutline(title: "One", feedURL: URL(string: "https://one.test/rss")!, folderName: "Must read")
        ]
        let applied = try await LibraryIngestActor(modelContainer: context.container).importOPML(outlines)
        #expect(applied.newSources == 1)
        #expect(applied.folderMembershipsAdded == 1)
        let stored = try ModelContext(context.container).fetch(FetchDescriptor<Feed>())
        let feed = try #require(stored.first)
        #expect(feed.title == "One")
        #expect(feed.folderName == "Must read")
    }
}
