//
//  MonoRssApp.swift
//  MonoRss
//
//  Created by Felix Lachapelle on 2026-08-29.
//

import SwiftUI
import SwiftData

@main
struct MonoRssApp: App {
    @Environment(\.scenePhase) private var scenePhase
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Feed.self,
            Article.self,
            SyncAccount.self,
            PendingSyncMutation.self,
        ])
        let useMemoryStore = ProcessInfo.processInfo.arguments.contains("-inMemoryStore")
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: useMemoryStore)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
                UserDefaults.standard.set(true, forKey: AppPreferenceKey.completedOnboarding)
                let context = ModelContext(container)
                let feedA = Feed(title: "Trail of Bits", websiteURL: URL(string: "https://example.com"), feedURL: URL(string: "https://example.com/feed")!, folderName: "Security")
                let feedB = Feed(title: "Swift.org", websiteURL: URL(string: "https://swift.org"), feedURL: URL(string: "https://swift.org/atom.xml")!, folderName: "Development")
                context.insert(feedA); context.insert(feedB)
                context.insert(Article(guid: "ui-1", title: "VMs Won’t Contain Cyber-Capable Agents", url: URL(string: "https://example.com/one"), publishedAt: .now.addingTimeInterval(-7200), summary: "Virtual machines were built to isolate workloads, not agents that can rewrite the machine from the inside.", contentHTML: "<p>Full offline article content for interface testing.</p>", estimatedReadingMinutes: 11, state: .current, feed: feedA))
                context.insert(Article(guid: "ui-2", title: "Swift concurrency without the noise", publishedAt: .now.addingTimeInterval(-3600), summary: "A second article.", estimatedReadingMinutes: 6, feed: feedB))
                context.insert(Article(guid: "ui-3", title: "What isolation still gets right", url: URL(string: "https://example.com/two"), publishedAt: .now.addingTimeInterval(-5400), summary: "A follow-up on hardware roots of trust.", estimatedReadingMinutes: 7, feed: feedA))
                let saved = Article(guid: "ui-saved", title: "Why SQLite is so reliable", publishedAt: .now.addingTimeInterval(-86400), summary: "A saved article for later.", estimatedReadingMinutes: 8, state: .saved, feed: feedA)
                saved.completedAt = .now.addingTimeInterval(-1800)
                context.insert(saved)
                let read = Article(guid: "ui-read", title: "Understanding Linux Namespaces", publishedAt: .now.addingTimeInterval(-172800), estimatedReadingMinutes: 9, state: .read, feed: feedB)
                read.completedAt = .now.addingTimeInterval(-600)
                context.insert(read)
                let skipped = Article(guid: "ui-skipped", title: "Some announcement that can wait", publishedAt: .now.addingTimeInterval(-259200), estimatedReadingMinutes: 4, state: .skipped, feed: feedA)
                skipped.completedAt = .now.addingTimeInterval(-90000)
                context.insert(skipped)
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
        }
        .modelContainer(sharedModelContainer)
        .backgroundTask(.appRefresh(BackgroundRefreshCoordinator.identifier)) {
            await BackgroundRefreshCoordinator.refresh(in: ModelContext(sharedModelContainer))
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { BackgroundRefreshCoordinator.schedule() }
        }
    }
}
