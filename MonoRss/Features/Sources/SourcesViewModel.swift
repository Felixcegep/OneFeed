import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class SourcesViewModel {
    private var context: ModelContext?
    private(set) var feeds: [Feed] = []
    var isPresentingAddSource = false

    func configure(with context: ModelContext) { self.context = context; reload() }
    func reload() {
        guard let context else { return }
        feeds = (try? context.fetch(FetchDescriptor<Feed>(sortBy: [SortDescriptor(\.title)]))) ?? []
    }
    var folders: [FeedFolderGroup] { FeedFolderGrouping.groups(from: feeds) }
    func feeds(in folderID: FeedFolderID) -> [Feed] {
        folders.first(where: { $0.folderID == folderID })?.feeds ?? []
    }
    func delete(at offsets: IndexSet) {
        guard let context else { return }
        for index in offsets { context.delete(feeds[index]) }
        try? context.save(); reload()
    }
}

@MainActor
@Observable
final class AddSourceViewModel {
    private let feedService: any FeedRepository
    var address = ""
    private(set) var isAdding = false
    var presentedError: String?

    init() { feedService = FeedService() }
    init(feedService: any FeedRepository) { self.feedService = feedService }

    func add(in context: ModelContext) async -> Bool {
        guard !isAdding else { return false }
        isAdding = true
        presentedError = nil
        do { _ = try await feedService.addSource(from: address, in: context); return true }
        catch { presentedError = error.localizedDescription; isAdding = false; return false }
    }
}

@MainActor
@Observable
final class SourceDetailViewModel {
    let feed: Feed
    private let context: ModelContext
    var isConfirmingRemoval = false

    init(feed: Feed, context: ModelContext) { self.feed = feed; self.context = context }
    var isEnabled: Bool {
        get { feed.isEnabled }
        set { feed.isEnabled = newValue; try? context.save() }
    }
    func remove() { context.delete(feed); try? context.save() }

    var recentArticles: [Article] {
        feed.articles
            .sorted { $0.publishedAt > $1.publishedAt }
            .prefix(20)
            .map { $0 }
    }
}
