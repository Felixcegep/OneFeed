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
                    systemImage: "star",
                    description: Text("Star an article and it will wait here.")
                )
            } else {
                List {
                    ForEach(viewModel.articles.filter(\.isStored)) { article in
                        Button {
                            viewModel.selectedArticle = article
                        } label: {
                            ArticleRow(article: article)
                        }
                        .buttonStyle(.plain)
                        .articleListRow()
                        .accessibilityHint("Opens the saved article")
                        .swipeActions {
                            Button("Return to Feed", systemImage: "arrow.uturn.backward") {
                                viewModel.restore(article)
                            }
                            .tint(.secondary)
                        }
                        .contextMenu {
                            Button("Return to Feed", systemImage: "arrow.uturn.backward") {
                                viewModel.restore(article)
                            }
                            Menu("Rate") {
                                ForEach(1...5, id: \.self) { stars in
                                    Button {
                                        guard article.isStored else { return }
                                        article.setRating(stars)
                                        try? modelContext.save()
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
                                        try? modelContext.save()
                                    }
                                }
                            }
                        }
                    }
                }
                .articleTimelineList()
            }
        }
        .navigationTitle("Saved")
        .navigationBarTitleDisplayMode(.large)
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
