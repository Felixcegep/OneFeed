import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Article> { $0.stateRawValue == "read" || $0.stateRawValue == "skipped" },
        sort: \Article.completedAt,
        order: .reverse
    ) private var history: [Article]
    @Query(sort: \NotInterestedEntry.recordedAt, order: .reverse) private var notInterested: [NotInterestedEntry]
    @State private var selectedArticle: Article?
    @State private var appliedSearch = ""
    /// Day groups stay put while the open story changes.
    @State private var dayCache = HistoryDayCache()

    private var trimmedQuery: String {
        appliedSearch.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Filters the history query already in memory. Search does not fetch.
    private var visibleHistory: [Article] {
        let query = trimmedQuery
        guard !query.isEmpty else { return history }
        return history.filter { article in
            guard article.isStored else { return false }
            return article.title.localizedStandardContains(query)
                || article.readingNote.localizedStandardContains(query)
                || (article.readingTakeawayLine?.localizedStandardContains(query) ?? false)
                || ArticlePresentation.sourceName(for: article).localizedStandardContains(query)
        }
    }

    private var days: [HistoryDay] {
        let stamp = historyStamp
        if dayCache.stamp == stamp { return dayCache.days }
        let days = HistoryViewModel.days(from: visibleHistory)
        dayCache.stamp = stamp
        dayCache.days = days
        return days
    }

    private var historyStamp: Int {
        var hasher = Hasher()
        hasher.combine(appliedSearch)
        hasher.combine(history.count)
        for article in history {
            hasher.combine(article.id)
            hasher.combine(article.stateRawValue)
            hasher.combine(article.completedAt)
            hasher.combine(article.publishedAt)
        }
        return hasher.finalize()
    }

    var body: some View {
        OneFeedReadingSplit(article: $selectedArticle) {
            OneFeedSearchHost("Search history", applied: $appliedSearch) {
                historyColumn
            }
        } reader: { article in
            ReaderView(
                article: article,
                onFinish: { _ in selectedArticle = nil },
                onClose: { selectedArticle = nil },
                onPutInQueue: {
                    putInQueue(article)
                    selectedArticle = nil
                }
            )
        }
    }

    private var historyColumn: some View {
        Group {
            if trimmedQuery.isEmpty && days.isEmpty && notInterested.isEmpty {
                EmptyLibraryState(
                    title: "No history yet",
                    systemImage: "clock",
                    description: "Read and skipped pieces appear here quietly."
                )
            } else if !trimmedQuery.isEmpty && days.isEmpty {
                EmptyLibraryState(
                    title: "No matches",
                    systemImage: "magnifyingglass",
                    description: "Try a title, note, or source name."
                )
            } else {
                List {
                    if trimmedQuery.isEmpty {
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
                    }

                    ForEach(days) { group in
                        Section {
                            ForEach(group.articles.filter(\.isStored)) { article in
                                Button { selectedArticle = article } label: {
                                    ArticleRow(article: article, status: article.historyStatus)
                                }
                                .buttonStyle(DirectoryRowButtonStyle())
                                .articleListRow(isSelected: selectedArticle?.id == article.id)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button("Put in Queue", systemImage: "square.stack") {
                                        putInQueue(article)
                                    }
                                    .tint(OneFeedTheme.accent)
                                }
                                .contextMenu {
                                    Button("Put in Queue", systemImage: "square.stack") {
                                        putInQueue(article)
                                    }
                                }
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
        .oneFeedScrollEdge()
        .background(OneFeedTheme.plaster)
    }

    private func putInQueue(_ article: Article) {
        guard article.isStored else { return }
        let motion: Animation? = OneFeedMotion.allowsMotion ? OneFeedMotion.list : nil
        withAnimation(motion) {
            try? ArticleQueueService().moveToQueue(article, in: modelContext)
        }
    }
}

private final class HistoryDayCache {
    var stamp = 0
    var days: [HistoryDay] = []
}
