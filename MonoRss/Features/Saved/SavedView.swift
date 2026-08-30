import SwiftUI
import SwiftData

struct SavedView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SavedViewModel()

    var body: some View {
        Group {
            if viewModel.articles.isEmpty {
                ContentUnavailableView(
                    "Nothing saved",
                    systemImage: "bookmark",
                    description: Text("Articles you save will wait here without folders or tags.")
                )
            } else {
                List(viewModel.articles) { article in
                    Button {
                        viewModel.selectedArticle = article
                    } label: {
                        ArticleRow(article: article)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the saved article")
                    .swipeActions {
                        Button("Return to queue", systemImage: "arrow.uturn.backward") {
                            viewModel.restore(article)
                        }
                        .tint(.secondary)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Saved")
        .navigationBarTitleDisplayMode(.inline)
        .task { viewModel.configure(with: modelContext) }
        .fullScreenCover(item: $viewModel.selectedArticle) { article in
            ReaderView(article: article) { state in
                viewModel.finishReading(article, as: state)
            }
        }
        .alert("Couldn’t update article", isPresented: Binding(get: { viewModel.presentedError != nil }, set: { if !$0 { viewModel.presentedError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(viewModel.presentedError ?? "") }
    }
}
