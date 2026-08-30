import Foundation
import SwiftData
import Testing
@testable import MonoRss

@MainActor
struct OPMLTests {
    private func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: Feed.self, Article.self, SyncAccount.self, PendingSyncMutation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func importFlattensNestedOutlinesAndSkipsDuplicateURLs() throws {
        let context = try context()
        let opml = """
        <?xml version="1.0"?><opml version="2.0"><body>
          <outline text="Tech"><outline text="One" xmlUrl="https://one.test/rss" />
            <outline title="Two" xmlUrl="https://two.test/feed" /></outline>
          <outline text="Duplicate" xmlUrl="https://one.test/rss" />
        </body></opml>
        """

        let inserted = try OPMLService().importDocument(Data(opml.utf8), in: context)
        #expect(inserted == 2)
        #expect(try context.fetchCount(FetchDescriptor<Feed>()) == 2)
        let feeds = try context.fetch(FetchDescriptor<Feed>(sortBy: [SortDescriptor(\.title)]))
        #expect(feeds.map(\.title) == ["One", "Two"])
    }

    @Test func exportEscapesTitlesAndURLs() throws {
        let context = try context()
        let feed = Feed(title: "A & B", feedURL: URL(string: "https://example.test/a?x=1&y=2")!)
        context.insert(feed)

        let document = OPMLService().exportDocument(feeds: [feed])
        let xml = String(decoding: document.data, as: UTF8.self)
        #expect(xml.contains("A &amp; B"))
        #expect(xml.contains("x=1&amp;y=2"))
        #expect(xml.contains("xmlUrl=\"https://example.test/a?x=1&amp;y=2\""))
    }
}
