//
//  OneFeedApp.swift
//  OneFeed
//
//  Created by Felix Lachapelle on 2026-08-29.
//

import SwiftUI
import SwiftData

@main
struct OneFeedApp: App {
    @Environment(\.scenePhase) private var scenePhase
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Feed.self,
            Article.self,
            SyncAccount.self,
            PendingSyncMutation.self,
            DailyDeck.self,
            DailyDeckItem.self,
            NotInterestedEntry.self,
        ])
        URLCache.shared = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 128 * 1024 * 1024
        )
        let useMemoryStore = ProcessInfo.processInfo.arguments.contains("-inMemoryStore")
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: useMemoryStore)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            if !ProcessInfo.processInfo.arguments.contains("-uiTesting") {
                let context = ModelContext(container)
                let seededVersion = UserDefaults.standard.integer(forKey: AppPreferenceKey.seedCatalogVersion)
                let legacySeeded = UserDefaults.standard.bool(forKey: AppPreferenceKey.didSeedTinyRSSCatalog)
                if seededVersion < FeedSeedCatalog.version || !legacySeeded {
                    _ = try? FeedSeedService().apply(in: context)
                    UserDefaults.standard.set(true, forKey: AppPreferenceKey.didSeedTinyRSSCatalog)
                    UserDefaults.standard.set(FeedSeedCatalog.version, forKey: AppPreferenceKey.seedCatalogVersion)
                } else {
                    Task { @MainActor in
                        _ = try? FeedSeedService().removeRetired(in: ModelContext(container))
                    }
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
                if ProcessInfo.processInfo.arguments.contains("-uiTestingOnboarding") {
                    UserDefaults.standard.set(false, forKey: AppPreferenceKey.completedOnboarding)
                } else {
                    UserDefaults.standard.set(true, forKey: AppPreferenceKey.completedOnboarding)
                }
                let context = ModelContext(container)
                let feedA = Feed(title: "Trail of Bits", websiteURL: URL(string: "https://example.com"), feedURL: URL(string: "https://example.com/feed")!, folderName: "Security")
                let feedB = Feed(title: "Swift.org", websiteURL: URL(string: "https://swift.org"), feedURL: URL(string: "https://swift.org/atom.xml")!, folderName: "Development")
                context.insert(feedA); context.insert(feedB)
                let deckArticle1 = Article(guid: "ui-1", title: "VMs Won’t Contain Cyber-Capable Agents", url: URL(string: "https://example.com/one"), publishedAt: .now.addingTimeInterval(-7200), summary: "Virtual machines were built to isolate workloads, not agents that can rewrite the machine from the inside.", contentHTML: "<p>Full offline article content for interface testing.</p>", estimatedReadingMinutes: 11, state: .current, feed: feedA)
                let deckArticle2 = Article(guid: "ui-2", title: "Swift concurrency without the noise", publishedAt: .now.addingTimeInterval(-3600), summary: "A second article.", estimatedReadingMinutes: 6, feed: feedB)
                let deckArticle3 = Article(guid: "ui-3", title: "What isolation still gets right", url: URL(string: "https://example.com/two"), publishedAt: .now.addingTimeInterval(-5400), summary: "A follow-up on hardware roots of trust.", estimatedReadingMinutes: 7, feed: feedA)
                context.insert(deckArticle1)
                context.insert(deckArticle2)
                context.insert(deckArticle3)
                if ProcessInfo.processInfo.arguments.contains("-uiTestingLayoutStress") {
                    deckArticle1.contentHTML = """
                    <h2>A reader built for attention</h2>
                    <p>This offline layout fixture checks paragraphs, links, tables and code without fetching a website.</p>
                    <blockquote>Readable content should fit the viewport at every text size.</blockquote>
                    <pre><code>let deliberatelyLongIdentifierForHorizontalScrolling = \"A long code sample that must scroll inside its own block, never move the whole reader sideways.\"</code></pre>
                    <table><tr><th>Feature</th><th>Expected presentation</th></tr><tr><td>Long text</td><td>Wraps within the reading column</td></tr></table>
                    <p><a href="https://example.com">An example link with a visible underline</a></p>
                    """ + String(repeating: "<p>A calm reading experience leaves room for the words. This paragraph provides enough content to inspect scrolling, line length and the fixed reader controls.</p>", count: 18)
                    for index in 1...12 {
                        let title = index == 12 ? "Last saved layout example" : (index == 2 ? "A deliberately long article title about how our perception of time changes when we slow down and read one story at a time" : "Saved layout example \(index)")
                        let sample = Article(guid: "ui-layout-\(index)", title: title, publishedAt: .now.addingTimeInterval(-Double(index) * 86400), estimatedReadingMinutes: index, state: .saved, feed: index.isMultiple(of: 2) ? feedA : feedB)
                        sample.completedAt = .now.addingTimeInterval(-Double(index + 2) * 3600)
                        context.insert(sample)
                    }
                }
                let todayDeck = DailyDeck(dayStart: Calendar.current.startOfDay(for: .now))
                context.insert(todayDeck)
                for (index, article) in [deckArticle1, deckArticle2, deckArticle3].enumerated() {
                    let status: ArticleState = index == 0 ? .current : .queued
                    context.insert(DailyDeckItem(position: index + 1, status: status, article: article, deck: todayDeck))
                }
                if !ProcessInfo.processInfo.arguments.contains("-uiTestingEmptyQueue") {
                    let saved = Article(guid: "ui-saved", title: "Why SQLite is so reliable", publishedAt: .now.addingTimeInterval(-86400), summary: "A saved article for later.", estimatedReadingMinutes: 8, state: .saved, feed: feedA)
                    saved.completedAt = .now.addingTimeInterval(-1800)
                    context.insert(saved)
                    let laterVideo = Article(
                        guid: "ui-later-video",
                        title: "A talk to watch later",
                        url: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"),
                        publishedAt: .now.addingTimeInterval(-3600),
                        estimatedReadingMinutes: 12,
                        state: .saved,
                        contentKind: "youtube",
                        durationSeconds: 720,
                        feed: feedB
                    )
                    laterVideo.completedAt = .now.addingTimeInterval(-600)
                    context.insert(laterVideo)
                }
                let read = Article(guid: "ui-read", title: "Understanding Linux Namespaces", publishedAt: .now.addingTimeInterval(-172800), estimatedReadingMinutes: 9, state: .read, feed: feedB)
                read.completedAt = .now.addingTimeInterval(-600)
                context.insert(read)
                let skipped = Article(guid: "ui-skipped", title: "Some announcement that can wait", publishedAt: .now.addingTimeInterval(-259200), estimatedReadingMinutes: 4, state: .skipped, feed: feedA)
                skipped.completedAt = .now.addingTimeInterval(-90000)
                context.insert(skipped)
                if ProcessInfo.processInfo.arguments.contains("-uiTestingNotInterested") {
                    skipped.notInterested = true
                    context.insert(NotInterestedEntry(
                        recordedAt: .now.addingTimeInterval(-4000),
                        articleTitle: skipped.title,
                        articleGUID: skipped.guid,
                        sourceTitle: feedA.title,
                        sourceFeedURL: feedA.feedURL.absoluteString,
                        feedID: feedA.id
                    ))
                    let second = Article(guid: "ui-noise", title: "A product roundup that can wait", publishedAt: .now.addingTimeInterval(-300000), estimatedReadingMinutes: 3, state: .skipped, notInterested: true, feed: feedA)
                    second.completedAt = .now.addingTimeInterval(-8000)
                    context.insert(second)
                    context.insert(NotInterestedEntry(
                        recordedAt: .now.addingTimeInterval(-8000),
                        articleTitle: second.title,
                        articleGUID: second.guid,
                        sourceTitle: feedA.title,
                        sourceFeedURL: feedA.feedURL.absoluteString,
                        feedID: feedA.id
                    ))
                }
                try? context.save()
            }
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                #if os(macOS)
                .frame(minWidth: 860, minHeight: 560)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        #endif
        .modelContainer(sharedModelContainer)
        #if os(iOS)
        .backgroundTask(.appRefresh(BackgroundRefreshCoordinator.identifier)) {
            await BackgroundRefreshCoordinator.refresh(in: ModelContext(sharedModelContainer))
        }
        #endif
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                BackgroundRefreshCoordinator.schedule()
                Task { await Self.syncLibrary(on: .background) }
            case .active:
                Task { await BackgroundRefreshCoordinator.refreshIfStale(in: ModelContext(sharedModelContainer)) }
                Task { await Self.syncLibrary(on: .active) }
            default:
                break
            }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Source…") {
                    NotificationCenter.default.post(name: OneFeedNotify.subscribe, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
                Button("Import EPUB or PDF…") {
                    NotificationCenter.default.post(
                        name: OneFeedNotify.addToQueue,
                        object: nil,
                        userInfo: ["pickFile": true]
                    )
                }
                Button("Refresh") {
                    NotificationCenter.default.post(name: OneFeedNotify.refresh, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
        #if os(macOS)
        Settings {
            SettingsView()
                .frame(minWidth: 520, minHeight: 480)
                .modelContainer(sharedModelContainer)
        }
        #endif
    }

    /// Drive automatic uses `sync(.automatic)`. Drive manual is a no-op here;
    /// Settings Sync Now still runs. Folder links keep flush/syncNow.
    private static func syncLibrary(on phase: ScenePhase) async {
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") { return }
        let library = LibrarySyncService.shared
        if library.linkedRecord?.usesGoogleDriveAPI == true {
            guard library.isAutoSyncEnabled else { return }
            _ = await library.sync(request: .automatic)
            return
        }
        switch phase {
        case .background:
            await library.flush()
        case .active:
            await library.syncNow()
        default:
            break
        }
    }
}
