import Foundation
import SwiftData
import Testing
@testable import OneFeed

@MainActor
struct QueueLinkServiceTests {
    @Test func addingALinkParksANewArticleInTheQueue() async throws {
        let context = try InMemoryStore.makeContext()
        let service = QueueLinkService(fetchesMetadata: false)
        let article = try await service.add(urlString: "https://example.com/long-read", in: context)

        #expect(article.state == .saved)
        #expect(article.isRemoteStarred)
        #expect(article.url == URL(string: "https://example.com/long-read"))
        #expect(article.contentKind == "article")
        let saved = ArticleState.saved.rawValue
        #expect(try context.fetchCount(FetchDescriptor<Article>(predicate: #Predicate { $0.stateRawValue == saved })) == 1)
    }

    @Test func addingAnExistingUnreadStoryMovesItToTheQueue() async throws {
        let context = try InMemoryStore.makeContext()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        let unread = Article(
            guid: "story-1",
            title: "A story",
            url: URL(string: "https://source.test/story"),
            state: .queued,
            feed: feed
        )
        context.insert(feed)
        context.insert(unread)
        try context.save()

        let parked = try await QueueLinkService(fetchesMetadata: false)
            .add(urlString: "https://source.test/story", in: context)
        #expect(parked.id == unread.id)
        #expect(unread.state == .saved)
    }

    @Test func titleFallsBackToHostWhenThePathIsEmpty() {
        let url = URL(string: "https://www.noema.media/")!
        #expect(QueueLinkService.fallbackTitle(for: url) == "noema.media")
    }

    @Test func parseTitleReadsOpenGraph() {
        let html = """
        <html><head>
        <meta property="og:title" content="A New Form Of Life">
        <title>Ignore me</title>
        </head></html>
        """
        #expect(QueueLinkService.parseTitle(in: html) == "A New Form Of Life")
    }
}
