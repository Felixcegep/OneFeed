import Foundation
import SwiftData
import Testing
@testable import OneFeed

@MainActor
struct NotInterestedLogTests {
    private func context() throws -> ModelContext {
        try InMemoryStore.makeContext()
    }

    @Test func recordingLogsTheArticleAndMarksIt() throws {
        let context = try context()
        let feed = Feed(
            title: "The Verge",
            websiteURL: URL(string: "https://www.theverge.com"),
            feedURL: URL(string: "https://www.theverge.com/rss/index.xml")!,
            folderName: "Must read"
        )
        context.insert(feed)
        let article = Article(
            guid: "verge-1",
            title: "Another gadget post",
            url: URL(string: "https://www.theverge.com/gadget"),
            state: .current,
            feed: feed
        )
        context.insert(article)
        try context.save()

        let entry = NotInterestedLog.record(article, in: context)
        #expect(article.notInterested)
        #expect(entry.articleTitle == "Another gadget post")
        #expect(entry.sourceTitle == "The Verge")
        #expect(entry.sourceFeedURL.contains("theverge.com"))
        #expect(try context.fetch(FetchDescriptor<NotInterestedEntry>()).count == 1)
    }

    @Test func recordingTheSameArticleUpdatesInsteadOfDuplicating() throws {
        let context = try context()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        context.insert(feed)
        let article = Article(
            guid: "same",
            title: "First title",
            url: URL(string: "https://source.test/one"),
            feed: feed
        )
        context.insert(article)

        NotInterestedLog.record(article, in: context, now: Date(timeIntervalSince1970: 10))
        article.title = "Edited title"
        NotInterestedLog.record(article, in: context, now: Date(timeIntervalSince1970: 20))

        let entries = try context.fetch(FetchDescriptor<NotInterestedEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.articleTitle == "Edited title")
        #expect(entries.first?.recordedAt == Date(timeIntervalSince1970: 20))
    }

    @Test func groupsSortByCountThenTitle() throws {
        let context = try context()
        let verge = Feed(title: "The Verge", feedURL: URL(string: "https://www.theverge.com/rss")!)
        let kottke = Feed(title: "kottke.org", feedURL: URL(string: "https://kottke.org/atom.xml")!)
        context.insert(verge)
        context.insert(kottke)
        for index in 1...3 {
            let article = Article(guid: "v-\(index)", title: "Verge \(index)", feed: verge)
            context.insert(article)
            NotInterestedLog.record(article, in: context)
        }
        let kottkeArticle = Article(guid: "k-1", title: "One", feed: kottke)
        context.insert(kottkeArticle)
        NotInterestedLog.record(kottkeArticle, in: context)

        let groups = NotInterestedLog.groups(from: NotInterestedLog.entries(in: context))
        #expect(groups.map(\.sourceTitle) == ["The Verge", "kottke.org"])
        #expect(groups.first?.count == 3)
    }

    @Test func snapshotMentionsRepeatsAndFolder() throws {
        let context = try context()
        let feed = Feed(
            title: "The Verge",
            feedURL: URL(string: "https://www.theverge.com/rss")!,
            folderName: "Must read"
        )
        context.insert(feed)
        let article = Article(guid: "v-1", title: "AI glasses are here", feed: feed)
        context.insert(article)
        NotInterestedLog.record(article, in: context)

        let text = NotInterestedLog.snapshot(in: context)
        #expect(text.contains("The Verge"))
        #expect(text.contains("AI glasses are here"))
        #expect(text.contains("Must read"))
    }

    @Test func archiveParksTheSourceOutOfToday() throws {
        let context = try context()
        let feed = Feed(
            title: "The Verge",
            feedURL: URL(string: "https://www.theverge.com/rss")!,
            folderName: "Must read",
            includeInToday: true
        )
        context.insert(feed)
        FolderEmoji.resetStored()
        defer {
            FolderStore.remove("Archive")
            FolderEmoji.resetStored()
        }

        NotInterestedLog.archive(feed, in: context)
        #expect(feed.folderName == "Archive")
        #expect(feed.includeInToday == false)
        #expect(feed.isEnabled)
        #expect(FolderStore.allNames(from: [feed]).contains("Archive"))
        #expect(FolderEmoji.glyph(for: "Archive") == "📦")
    }

    @Test func markNotInterestedSkipsTheArticle() throws {
        let context = try context()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        context.insert(feed)
        let current = Article(guid: "current", title: "Current", state: .current, feed: feed)
        let next = Article(guid: "next", title: "Next", publishedAt: .now.addingTimeInterval(10), feed: feed)
        context.insert(current)
        context.insert(next)
        try context.save()

        ArticleActions.markNotInterested(current, in: context)
        #expect(current.state == .skipped)
        #expect(current.notInterested)
        #expect(current.completedAt != nil)
        #expect(try context.fetch(FetchDescriptor<NotInterestedEntry>()).count == 1)
    }

    @Test func logSurvivesArticlePurge() throws {
        let context = try context()
        let feed = Feed(title: "Source", feedURL: URL(string: "https://source.test/rss")!)
        context.insert(feed)
        let article = Article(
            guid: "old",
            title: "Old noise",
            publishedAt: .now.addingTimeInterval(-30 * 86_400),
            state: .skipped,
            feed: feed
        )
        context.insert(article)
        NotInterestedLog.record(article, in: context)
        _ = try ArticleRetentionService().purge(in: context, olderThanDays: 7)
        #expect(try context.fetch(FetchDescriptor<Article>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<NotInterestedEntry>()).count == 1)
    }
}

@MainActor
struct NotInterestedLibrarianTests {
    @Test func librarianListsTheLogAndArchivesASource() async throws {
        let context = try InMemoryStore.makeContext()
        let feed = Feed(
            title: "The Verge",
            feedURL: URL(string: "https://www.theverge.com/rss/index.xml")!,
            folderName: "Must read"
        )
        context.insert(feed)
        let article = Article(guid: "v-1", title: "Gadget roundup", feed: feed)
        context.insert(article)
        NotInterestedLog.record(article, in: context)
        defer {
            FolderStore.remove("Archive")
            FolderEmoji.resetStored()
        }

        let librarian = GeminiLibrarian()
        let listed = await librarian.perform(
            GeminiFunctionCall(name: "list_not_interested", arguments: [:]),
            in: context,
            allowRemoval: false
        )
        #expect(listed.ok)
        #expect(listed.message.contains("The Verge"))
        #expect(listed.message.contains("Gadget roundup"))

        let archived = await librarian.perform(
            GeminiFunctionCall(name: "archive_source", arguments: ["source": "The Verge"]),
            in: context,
            allowRemoval: false
        )
        #expect(archived.ok)
        #expect(feed.folderName == "Archive")
        #expect(feed.includeInToday == false)

        let again = await librarian.perform(
            GeminiFunctionCall(name: "archive_source", arguments: ["source": "The Verge"]),
            in: context,
            allowRemoval: false
        )
        #expect(again.message.contains("already in Archive"))
    }

    @Test func skipUndoCanFileNotInterestedAndStillRestore() throws {
        let context = try context()
        let article = Article(
            guid: "skip-1",
            title: "A story to set aside",
            url: URL(string: "https://example.com/skip"),
            state: .current
        )
        context.insert(article)
        try context.save()

        ReadingUndo.begin(article, in: context)
        article.state = .skipped
        article.completedAt = .now
        ReadingUndo.commit(article, in: context)

        let center = ReadingUndoCenter.shared
        #expect(center.offer?.title == "Skipped")
        #expect(center.offer?.strongerTitle == "Not interested")
        center.performStronger()
        #expect(article.notInterested)
        #expect(center.offer?.title == "Not interested")
        #expect(center.offer?.strongerTitle == nil)
        center.performStronger()
        #expect(try context.fetch(FetchDescriptor<NotInterestedEntry>()).count == 1)

        center.performUndo()
        #expect(article.state == .current)
        #expect(article.notInterested == false)
        #expect(try context.fetch(FetchDescriptor<NotInterestedEntry>()).isEmpty)
        #expect(center.offer == nil)
    }
}
