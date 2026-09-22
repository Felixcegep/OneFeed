import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(
        filter: #Predicate<Article> { $0.stateRawValue == "read" || $0.stateRawValue == "skipped" },
        sort: \Article.completedAt,
        order: .reverse
    ) private var history: [Article]
    @Query(sort: \NotInterestedEntry.recordedAt, order: .reverse) private var notInterested: [NotInterestedEntry]
    @State private var selectedArticle: Article?

    private var days: [HistoryDay] {
        HistoryViewModel.days(from: history)
    }

    var body: some View {
        OneFeedReadingSplit(article: $selectedArticle) {
            historyColumn
        } reader: { article in
            ReaderView(article: article, onFinish: { _ in
                selectedArticle = nil
            }, onClose: {
                selectedArticle = nil
            })
        }
    }

    private var historyColumn: some View {
        Group {
            if days.isEmpty && notInterested.isEmpty {
                EmptyLibraryState(
                    title: "No history yet",
                    systemImage: "clock",
                    description: "Read and skipped pieces appear here quietly."
                )
            } else {
                List {
                    Section {
                        NavigationLink {
                            NotInterestedView()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Not interested")
                                    .font(.body)
                                    .foregroundStyle(OneFeedTheme.ink)
                                Text(notInterested.isEmpty
                                     ? "Set aside, grouped by source"
                                     : notInterested.count == 1 ? "1 set aside" : "\(notInterested.count) set aside")
                                    .font(.subheadline)
                                    .foregroundStyle(OneFeedTheme.graphite)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listRowBackground(OneFeedTheme.paper)

                    ForEach(days) { group in
                        Section {
                            ForEach(group.articles.filter(\.isStored)) { article in
                                Button { selectedArticle = article } label: {
                                    ArticleRow(article: article, status: article.historyStatus)
                                }
                                .buttonStyle(DirectoryRowButtonStyle())
                                .articleListRow(isSelected: selectedArticle?.id == article.id)
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
    }
}
