import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(
        filter: #Predicate<Article> { $0.stateRawValue == "read" || $0.stateRawValue == "skipped" },
        sort: \Article.completedAt,
        order: .reverse
    ) private var history: [Article]
    @State private var selectedArticle: Article?

    private var days: [HistoryDay] {
        HistoryViewModel.days(from: history)
    }

    var body: some View {
        Group {
            if days.isEmpty {
                EmptyLibraryState(
                    title: "No history yet",
                    systemImage: "clock",
                    description: "Read and skipped pieces appear here quietly."
                )
            } else {
                List {
                    ForEach(days) { group in
                        Section {
                            ForEach(group.articles.filter(\.isStored)) { article in
                                Button { selectedArticle = article } label: {
                                    ArticleRow(article: article, status: article.state == .read ? "Read" : "Skipped")
                                }
                                .buttonStyle(DirectoryRowButtonStyle())
                                .articleListRow()
                            }
                        } header: {
                            GallerySectionHeader(text: group.label)
                        }
                    }
                }
                .oneFeedGroupedListStyle()
            }
        }
        .navigationTitle("History")
        .oneFeedInlineTitle()
        .oneFeedPaperToolbar()
        .background(OneFeedTheme.plaster)
        .oneFeedArticleCover(item: $selectedArticle) { article in
            ReaderView(article: article) { _ in selectedArticle = nil }
        }
    }
}
