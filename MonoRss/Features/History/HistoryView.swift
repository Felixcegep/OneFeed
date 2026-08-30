import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = HistoryViewModel()

    var body: some View {
        Group {
            if viewModel.days.isEmpty {
                ContentUnavailableView(
                    "No history yet",
                    systemImage: "clock",
                    description: Text("Read and skipped articles appear here quietly.")
                )
            } else {
                List {
                    ForEach(viewModel.days) { group in
                        Section(group.label) {
                            ForEach(group.articles) { article in
                                ArticleRow(article: article, status: article.state == .read ? "Read" : "Skipped")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .task { viewModel.load(from: modelContext) }
    }
}
