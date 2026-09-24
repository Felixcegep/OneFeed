import Foundation
import SwiftData
import Testing
@testable import OneFeed

@MainActor
struct SemanticDeckTests {
    @Test func oneStoryClusterFillsASingleTodaySlot() throws {
        let context = try InMemoryStore.makeContext()
        let clusterID = UUID()
        var clustered: [Article] = []

        for index in 0..<4 {
            let feed = Feed(
                title: "Source \(index)",
                feedURL: URL(string: "https://source-\(index).test/rss")!,
                includeInToday: true
            )
            context.insert(feed)
            let article = Article(
                guid: "story-\(index)",
                title: "Shared story \(index)",
                url: URL(string: "https://source-\(index).test/stories/\(index)")!,
                publishedAt: .now,
                state: .queued,
                feed: feed
            )
            context.insert(article)
            clustered.append(article)
            context.insert(ContentMemory(
                identityKey: ArticleIdentity.identityKey(for: article),
                title: article.title,
                relationshipRaw: ContentRelationship.sameStory.rawValue,
                storyClusterID: clusterID
            ))
        }

        let otherFeed = Feed(
            title: "Other",
            feedURL: URL(string: "https://other.test/rss")!,
            includeInToday: true
        )
        context.insert(otherFeed)
        let other = Article(
            guid: "other-topic",
            title: "A different topic",
            url: URL(string: "https://other.test/pieces/one")!,
            publishedAt: .now,
            state: .queued,
            feed: otherFeed
        )
        context.insert(other)
        context.insert(ContentMemory(
            identityKey: ArticleIdentity.identityKey(for: other),
            title: other.title,
            relationshipRaw: ContentRelationship.new.rawValue,
            storyClusterID: nil
        ))

        let deck = try DailyDeckService().generateIfNeeded(in: context)
        let selected = deck.items.compactMap(\.article)
        let clusteredIDs = Set(clustered.map(\.id))
        let fromCluster = selected.filter { clusteredIDs.contains($0.id) }

        #expect(fromCluster.count == 1)
        #expect(deck.items.count == 2)
        #expect(selected.contains { $0.id == other.id })

        let memories = try context.fetch(FetchDescriptor<ContentMemory>())
        let shown = fromCluster[0]
        let caption = StoryGrouping.captions(
            for: [shown],
            memories: memories,
            openArticles: clustered + [other]
        )[shown.id]
        #expect(caption == "3 more sources about this story")
    }
}
