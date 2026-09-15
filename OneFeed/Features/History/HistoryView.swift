import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = HistoryViewModel()

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
                        Section(group.label) {
                            ForEach(group.articles.filter(\.isStored)) { article in
                                ArticleRow(article: article, status: article.state == .read ? "Read" : "Skipped")
                            }
                        }
                    }
                }
                .oneFeedGroupedListStyle()
            }
        }
        .navigationTitle("History")
        .oneFeedInlineTitle()
        .task { viewModel.load(from: modelContext) }
    }
}
