import SwiftData
import SwiftUI

@MainActor
enum ArticleActions {
    static func apply(
        _ state: ArticleState,
        to article: Article,
        in context: ModelContext
    ) throws {
        guard article.isStored, article.state != state else { return }
        if state == .skipped {
            ReadingUndo.begin(article, in: context)
        }
        let queue = ArticleQueueService()
        let sync: any FreshRSSSyncing = FreshRSSSyncService()
        sync.enqueueMutation(for: article, transition: state, in: context)
        let motion: Animation? = OneFeedMotion.allowsMotion ? OneFeedMotion.list : nil
        try withAnimation(motion) {
            try queue.complete(article, as: state, in: context)
        }
        try syncTodayDeck(article, to: state, in: context)
        if state == .skipped {
            ReadingUndo.commit(article, in: context)
        }
    }

    @discardableResult
    static func markNotInterested(_ article: Article, in context: ModelContext) -> Bool {
        ReadingUndo.begin(article, in: context)
        NotInterestedLog.record(article, in: context)
        do {
            try apply(.skipped, to: article, in: context)
            return true
        } catch {
            return false
        }
    }

    static func rate(_ article: Article, stars: Int, in context: ModelContext) throws {
        guard article.isStored else { return }
        let next = min(5, max(0, stars))
        guard article.rating != next else { return }
        let previous = article.rating
        article.setRating(next)
        LibraryChange.note(article)
        do {
            try context.save()
        } catch {
            article.setRating(previous)
            throw error
        }
    }

    private static func syncTodayDeck(_ article: Article, to state: ArticleState, in context: ModelContext) throws {
        guard let deck = try? DailyDeckService().todayDeck(in: context),
              let item = deck.items.first(where: { $0.article?.id == article.id })
        else { return }
        item.status = state
        let stillHasCurrent = deck.items.contains { $0.status == .current && $0.article?.isStored == true }
        if !stillHasCurrent,
           let next = deck.items
            .filter({ $0.status == .queued && $0.article?.isStored == true })
            .sorted(by: { $0.position < $1.position })
            .first {
            next.status = .current
            if let article = next.article {
                article.state = .current
                article.firstDisplayedAt = article.firstDisplayedAt ?? .now
                LibraryChange.note(article)
            }
            WidgetSnapshotStore.write(article: next.article)
        }
        try context.save()
    }
}

struct ArticleSwipeActions: ViewModifier {
    let article: Article
    let context: ModelContext
    var onChanged: (() -> Void)? = nil
    @State private var ratingError: String?

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button("Done", systemImage: "checkmark") {
                    guard (try? ArticleActions.apply(.read, to: article, in: context)) != nil else { return }
                    onChanged?()
                }
                .tint(OneFeedTheme.sage)
                Button("Skip", systemImage: "forward") {
                    guard (try? ArticleActions.apply(.skipped, to: article, in: context)) != nil else { return }
                    onChanged?()
                }
                .tint(OneFeedTheme.stone)
                Button("Not interested", systemImage: "hand.thumbsdown") {
                    guard ArticleActions.markNotInterested(article, in: context) else { return }
                    onChanged?()
                }
                .tint(OneFeedTheme.graphite)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button("Queue", systemImage: "square.stack") {
                    guard (try? ArticleActions.apply(.saved, to: article, in: context)) != nil else { return }
                    onChanged?()
                }
                .tint(OneFeedTheme.accent)
            }
            .contextMenu {
                Button("Add to Queue", systemImage: "square.stack") {
                    guard (try? ArticleActions.apply(.saved, to: article, in: context)) != nil else { return }
                    onChanged?()
                }
                Button("Done", systemImage: "checkmark") {
                    guard (try? ArticleActions.apply(.read, to: article, in: context)) != nil else { return }
                    onChanged?()
                }
                Button("Skip", systemImage: "forward") {
                    guard (try? ArticleActions.apply(.skipped, to: article, in: context)) != nil else { return }
                    onChanged?()
                }
                Button("Not interested", systemImage: "hand.thumbsdown") {
                    guard ArticleActions.markNotInterested(article, in: context) else { return }
                    onChanged?()
                }
                Menu("Rate") {
                    ForEach(1...5, id: \.self) { stars in
                        Button {
                            saveRating(stars)
                        } label: {
                            Label(
                                "\(stars) star\(stars == 1 ? "" : "s")",
                                systemImage: article.rating >= stars ? "star.fill" : "star"
                            )
                        }
                    }
                    if article.rating > 0 {
                        Button("Clear rating", systemImage: "star.slash") {
                            saveRating(0)
                        }
                    }
                }
            }
            .alert("Couldn’t save that rating", isPresented: Binding(
                get: { ratingError != nil },
                set: { if !$0 { ratingError = nil } }
            )) {
                Button("OK", role: .cancel) { ratingError = nil }
            } message: {
                Text(ratingError ?? "")
            }
    }

    private func saveRating(_ stars: Int) {
        do {
            try ArticleActions.rate(article, stars: stars, in: context)
            onChanged?()
        } catch {
            ratingError = UserFacingFailure.message(for: error, fallback: "Couldn’t save that rating.")
        }
    }
}

extension View {
    func articleActions(
        for article: Article,
        in context: ModelContext,
        onChanged: (() -> Void)? = nil
    ) -> some View {
        modifier(ArticleSwipeActions(article: article, context: context, onChanged: onChanged))
    }
}
