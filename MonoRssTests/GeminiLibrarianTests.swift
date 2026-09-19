import Foundation
import SwiftData
import Testing
@testable import OneFeed

struct GeminiLibrarianTests {
    @Test func parseGenerateReadsFunctionCallsAndKeepsThoughtSignature() throws {
        let payload = """
        {"candidates":[{"content":{"role":"model","parts":[
          {"thoughtSignature":"sig-1","functionCall":{"name":"add_source","args":{"url":"https://kottke.org","folder":"Must read"}}},
          {"text":"Adding that now."}
        ]}}]}
        """.data(using: .utf8)!

        let result = try GeminiClient.parseGenerate(from: payload)
        #expect(result.text == "Adding that now.")
        #expect(result.functionCalls.count == 1)
        #expect(result.functionCalls.first?.name == "add_source")
        #expect(result.functionCalls.first?.string("url") == "https://kottke.org")
        #expect(result.functionCalls.first?.string("folder") == "Must read")
        let content = result.modelContent
        let parts = try #require(content["parts"] as? [[String: Any]])
        #expect(parts.first?["thoughtSignature"] as? String == "sig-1")
    }

    @Test func parseGenerateFlattensBooleanArgs() throws {
        let payload = """
        {"candidates":[{"content":{"parts":[
          {"functionCall":{"name":"update_source","args":{"source":"The Verge","include_in_today":false}}}
        ]}}]}
        """.data(using: .utf8)!
        let result = try GeminiClient.parseGenerate(from: payload)
        #expect(result.functionCalls.first?.bool("include_in_today") == false)
    }

    @Test func parseGenerateSurfacesAPIErrors() {
        let error = #"{"error":{"message":"API key expired"}}"#.data(using: .utf8)!
        do {
            _ = try GeminiClient.parseGenerate(from: error)
            Issue.record("Expected a Gemini API error")
        } catch let thrown as GeminiClientError {
            #expect(thrown == .api("API key expired"))
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test func matchFeedsPrefersExactTitleThenHost() {
        let verge = Feed(
            title: "The Verge",
            websiteURL: URL(string: "https://www.theverge.com"),
            feedURL: URL(string: "https://www.theverge.com/rss/index.xml")!
        )
        let vergeNotes = Feed(
            title: "The Verge Newsletter",
            websiteURL: URL(string: "https://www.theverge.com/newsletter"),
            feedURL: URL(string: "https://www.theverge.com/newsletter/rss")!
        )
        let kottke = Feed(
            title: "kottke.org",
            websiteURL: URL(string: "https://kottke.org"),
            feedURL: URL(string: "https://kottke.org/atom.xml")!
        )

        if case .one(let id) = GeminiLibraryTools.matchFeeds(query: "The Verge", in: [verge, vergeNotes, kottke]) {
            #expect(id == verge.id)
        } else {
            Issue.record("Expected an exact title match")
        }

        if case .one(let id) = GeminiLibraryTools.matchFeeds(query: "kottke.org", in: [verge, kottke]) {
            #expect(id == kottke.id)
        } else {
            Issue.record("Expected a host match")
        }

        if case .many(let titles) = GeminiLibraryTools.matchFeeds(query: "Verge", in: [verge, vergeNotes]) {
            #expect(titles.contains("The Verge"))
            #expect(titles.contains("The Verge Newsletter"))
        } else {
            Issue.record("Expected an ambiguous match")
        }
    }

    @Test func snapshotListsFoldersAndFlags() {
        let paused = Feed(
            title: "Noise",
            feedURL: URL(string: "https://noise.test/rss")!,
            isEnabled: false,
            folderName: "Must read"
        )
        let today = Feed(
            title: "Essay",
            websiteURL: URL(string: "https://essay.test"),
            feedURL: URL(string: "https://essay.test/feed")!,
            folderName: "Must read",
            includeInToday: false
        )
        let text = GeminiLibraryTools.snapshot(feeds: [paused, today], folderNames: ["Must read", "Builders"])
        #expect(text.contains("Must read"))
        #expect(text.contains("Builders"))
        #expect(text.contains("paused"))
        #expect(text.contains("not in Today"))
        #expect(text.contains("(empty)"))
    }

    @Test @MainActor func librarianMovesCreatesAndUpdatesSources() async throws {
        let context = try InMemoryStore.makeContext()
        let feed = Feed(
            title: "The Verge",
            websiteURL: URL(string: "https://www.theverge.com"),
            feedURL: URL(string: "https://www.theverge.com/rss/index.xml")!,
            folderName: "Must read"
        )
        context.insert(feed)
        try context.save()
        FolderStore.remember("Must read")
        defer {
            FolderStore.remove("Newsletters")
            FolderStore.remove("Skim")
            FolderStore.remove("Librarian Skim")
            FolderEmoji.resetStored()
        }

        let librarian = GeminiLibrarian(
            feedService: InsertingFeedRepository(),
            freshRSSService: LocalFreshRSSService()
        )

        let moved = await librarian.perform(
            GeminiFunctionCall(name: "move_source", arguments: ["source": "The Verge", "folder": "Librarian Skim"]),
            in: context,
            allowRemoval: false
        )
        #expect(moved.ok)
        #expect(feed.folderName == "Librarian Skim")

        let created = await librarian.perform(
            GeminiFunctionCall(name: "create_folder", arguments: ["name": "Newsletters", "emoji": "✉️"]),
            in: context,
            allowRemoval: false
        )
        #expect(created.ok)
        #expect(FolderStore.allNames(from: [feed]).contains("Newsletters"))
        #expect(FolderEmoji.glyph(for: "Newsletters") == "✉️")

        let updated = await librarian.perform(
            GeminiFunctionCall(name: "update_source", arguments: [
                "source": "The Verge",
                "include_in_today": "false",
                "enabled": "true"
            ]),
            in: context,
            allowRemoval: false
        )
        #expect(updated.ok)
        #expect(feed.includeInToday == false)
        #expect(feed.isEnabled)

        let renamed = await librarian.perform(
            GeminiFunctionCall(name: "rename_folder", arguments: ["from": "Librarian Skim", "to": "À scanner"]),
            in: context,
            allowRemoval: false
        )
        #expect(renamed.ok)
        #expect(feed.folderName == "À scanner")
    }

    @Test @MainActor func librarianAddAndConfirmedRemoveChangeTheLibrary() async throws {
        let context = try InMemoryStore.makeContext()
        let librarian = GeminiLibrarian(
            feedService: InsertingFeedRepository(),
            freshRSSService: LocalFreshRSSService()
        )
        defer { FolderStore.remove("Librarian Inbox") }

        let added = await librarian.perform(
            GeminiFunctionCall(name: "add_source", arguments: [
                "url": "https://kottke.org",
                "folder": "Librarian Inbox"
            ]),
            in: context,
            allowRemoval: false
        )
        #expect(added.ok)
        let feeds = try context.fetch(FetchDescriptor<Feed>())
        #expect(feeds.count == 1)
        #expect(feeds.first?.folderName == "Librarian Inbox")

        let pending = await librarian.perform(
            GeminiFunctionCall(name: "remove_source", arguments: ["source": "kottke.org"]),
            in: context,
            allowRemoval: false
        )
        #expect(pending.needsConfirmation)
        #expect(try context.fetch(FetchDescriptor<Feed>()).count == 1)

        let removed = await librarian.perform(
            GeminiFunctionCall(name: "remove_source", arguments: ["source": "kottke.org"]),
            in: context,
            allowRemoval: true
        )
        #expect(removed.ok)
        #expect(try context.fetch(FetchDescriptor<Feed>()).isEmpty)
    }

    @Test @MainActor func librarianViewModelAsksBeforeRemoving() async throws {
        let context = try InMemoryStore.makeContext()
        let feed = Feed(
            title: "The Verge",
            feedURL: URL(string: "https://www.theverge.com/rss/index.xml")!
        )
        context.insert(feed)
        try context.save()

        let gemini = ScriptedGemini(results: [
            .toolCalls([GeminiFunctionCall(name: "remove_source", arguments: ["source": "The Verge"])]),
            .textReply("Removed The Verge.")
        ])
        let viewModel = ExperimentalLibrarianViewModel(
            gemini: gemini,
            librarian: GeminiLibrarian(
                feedService: InsertingFeedRepository(),
                freshRSSService: LocalFreshRSSService()
            ),
            requireAPIKey: false
        )
        viewModel.configure(with: context)
        viewModel.draft = "Remove The Verge"
        await viewModel.send()

        #expect(viewModel.pendingRemoval?.title == "The Verge")
        #expect(try context.fetch(FetchDescriptor<Feed>()).count == 1)

        await viewModel.confirmRemoval()
        #expect(viewModel.pendingRemoval == nil)
        #expect(try context.fetch(FetchDescriptor<Feed>()).isEmpty)
        #expect(viewModel.messages.contains { message in
            if case .assistant(let text) = message.kind { return text == "Removed The Verge." }
            return false
        })
    }
}

@MainActor
private final class InsertingFeedRepository: FeedRepository {
    func addSource(from input: String, folderName: String?, in context: ModelContext) async throws -> Feed {
        guard let url = FeedService.normalizedURL(from: input) else { throw FeedServiceError.invalidAddress }
        let feed = Feed(
            title: url.host() ?? input,
            websiteURL: url,
            feedURL: url,
            folderName: folderName
        )
        context.insert(feed)
        if let folderName { FolderStore.remember(folderName) }
        try context.save()
        return feed
    }

    func refresh(_ feed: Feed, in context: ModelContext) async throws {}
    func refreshAll(in context: ModelContext, progress: RefreshProgress?) async throws {}
}

@MainActor
private final class LocalFreshRSSService: FreshRSSSyncing {
    func connect(serverURL: URL, username: String, password: String, in context: ModelContext) async throws -> SyncAccount {
        SyncAccount(provider: .freshRSS, serverURL: serverURL, username: username)
    }
    func disconnect(account: SyncAccount, in context: ModelContext) async throws {}
    func sync(account: SyncAccount, in context: ModelContext, progress: RefreshProgress?) async throws {}
    func enqueueMutation(for article: Article, transition: ArticleState, in context: ModelContext) {}
    func addSubscription(from input: String, folderName: String?, in context: ModelContext) async throws -> Feed {
        guard let url = FeedService.normalizedURL(from: input) else { throw FeedServiceError.invalidAddress }
        let feed = Feed(title: url.host() ?? input, websiteURL: url, feedURL: url, folderName: folderName)
        context.insert(feed)
        try context.save()
        return feed
    }
    func removeSubscription(_ feed: Feed, in context: ModelContext) async throws {
        LibraryChange.noteRemovedFeed(feed)
        context.delete(feed)
        try context.save()
    }
    func subscribeLocalFeeds(in context: ModelContext) async throws {}
}

private final class ScriptedGemini: GeminiConversing, @unchecked Sendable {
    private var results: [GeminiGenerateResult]

    init(results: [GeminiGenerateResult]) {
        self.results = results
    }

    func generateLibrarian(contentsJSON: Data, systemInstruction: String) async throws -> GeminiGenerateResult {
        guard !results.isEmpty else { throw GeminiClientError.emptyReply }
        return results.removeFirst()
    }
}
