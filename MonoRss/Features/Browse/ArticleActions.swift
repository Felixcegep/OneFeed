import SwiftData
import SwiftUI

@MainActor
enum ArticleActions {
    static func apply(
        _ state: ArticleState,
        to article: Article,
        in context: ModelContext
    ) {
        let queue = ArticleQueueService()
        let sync: any FreshRSSSyncing = FreshRSSSyncService()
        sync.enqueueMutation(for: article, transition: state, in: context)
        do { try queue.complete(article, as: state, in: context) }
        catch { }
    }
}

struct ArticleSwipeActions: ViewModifier {
    let article: Article
    let context: ModelContext

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button("Done", systemImage: "checkmark") {
                    ArticleActions.apply(.read, to: article, in: context)
                }
                .tint(.green)
                Button("Skip", systemImage: "forward") {
                    ArticleActions.apply(.skipped, to: article, in: context)
                }
                .tint(.secondary)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button("Save", systemImage: "bookmark") {
                    ArticleActions.apply(.saved, to: article, in: context)
                }
                .tint(.orange)
            }
            .contextMenu {
                Button("Save", systemImage: "bookmark") {
                    ArticleActions.apply(.saved, to: article, in: context)
                }
                Button("Done", systemImage: "checkmark") {
                    ArticleActions.apply(.read, to: article, in: context)
                }
                Button("Skip", systemImage: "forward") {
                    ArticleActions.apply(.skipped, to: article, in: context)
                }
            }
    }
}

extension View {
    func articleActions(for article: Article, in context: ModelContext) -> some View {
        modifier(ArticleSwipeActions(article: article, context: context))
    }
}
