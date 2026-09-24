import SwiftData
import SwiftUI

@MainActor
enum ArticleActions {
    static func apply(
        _ state: ArticleState,
        to article: Article,
        in context: ModelContext
    ) {
        guard article.isStored else { return }
        if state == .skipped {
            ReadingUndo.begin(article, in: context)
        }
        let queue = ArticleQueueService()
        let sync: any FreshRSSSyncing = FreshRSSSyncService()
        sync.enqueueMutation(for: article, transition: state, in: context)
        let motion: Animation? = OneFeedMotion.allowsMotion ? OneFeedMotion.list : nil
        do {
            try withAnimation(motion) {
                try queue.complete(article, as: state, in: context)
            }
        } catch {
            return
        }
        syncTodayDeck(article, to: state, in: context)
        if state == .skipped {
            ReadingUndo.commit(article, in: context)
        }
    }

    static func markNotInterested(_ article: Article, in context: ModelContext) {
        ReadingUndo.begin(article, in: context)
        NotInterestedLog.record(article, in: context)
        apply(.skipped, to: article, in: context)
    }

    private static func syncTodayDeck(_ article: Article, to state: ArticleState, in context: ModelContext) {
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
        try? context.save()
    }
}

struct ArticleSwipeActions: ViewModifier {
    let article: Article
    let context: ModelContext
    var onChanged: (() -> Void)? = nil

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button("Done", systemImage: "checkmark") {
                    ArticleActions.apply(.read, to: article, in: context)
                    onChanged?()
                }
                .tint(OneFeedTheme.sage)
                Button("Skip", systemImage: "forward") {
                    ArticleActions.apply(.skipped, to: article, in: context)
                    onChanged?()
                }
                .tint(OneFeedTheme.stone)
                Button("Not interested", systemImage: "hand.thumbsdown") {
                    ArticleActions.markNotInterested(article, in: context)
                    onChanged?()
                }
                .tint(OneFeedTheme.graphite)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button("Queue", systemImage: "square.stack") {
                    ArticleActions.apply(.saved, to: article, in: context)
                    onChanged?()
                }
                .tint(OneFeedTheme.accent)
            }
            .contextMenu {
                Button("Add to Queue", systemImage: "square.stack") {
                    ArticleActions.apply(.saved, to: article, in: context)
                    onChanged?()
                }
                Button("Done", systemImage: "checkmark") {
                    ArticleActions.apply(.read, to: article, in: context)
                    onChanged?()
                }
                Button("Skip", systemImage: "forward") {
                    ArticleActions.apply(.skipped, to: article, in: context)
                    onChanged?()
                }
                Button("Not interested", systemImage: "hand.thumbsdown") {
                    ArticleActions.markNotInterested(article, in: context)
                    onChanged?()
                }
                Menu("Rate") {
                    ForEach(1...5, id: \.self) { stars in
                        Button {
                            article.setRating(stars)
                            try? context.save()
                        } label: {
                            Label(
                                "\(stars) star\(stars == 1 ? "" : "s")",
                                systemImage: article.rating >= stars ? "star.fill" : "star"
                            )
                        }
                    }
                    if article.rating > 0 {
                        Button("Clear rating", systemImage: "star.slash") {
                            article.setRating(0)
                            try? context.save()
                        }
                    }
                }
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
