import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = HistoryViewModel()
    @State private var selectedArticle: Article?

    var body: some View {
        Group {
            if viewModel.days.isEmpty {
                EmptyLibraryState(
                    title: "No history yet",
                    systemImage: "clock",
                    description: "Read and skipped pieces appear here quietly."
                )
            } else {
                List {
                    ForEach(viewModel.days) { group in
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
        .task { viewModel.load(from: modelContext) }
        .oneFeedArticleCover(item: $selectedArticle) { article in
            ReaderView(article: article) { _ in selectedArticle = nil }
        }
    }
}
