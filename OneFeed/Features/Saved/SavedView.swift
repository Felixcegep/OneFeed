import SwiftUI
import SwiftData

struct SavedView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SavedViewModel()
    @State private var isAdding = false

    private var waiting: [Article] {
        viewModel.articles.filter(\.isStored)
    }

    private var upNext: Article? { waiting.first }

    var body: some View {
        Group {
            if waiting.isEmpty {
                empty
            } else {
                List {
                    if let upNext {
                        Section {
                            Button { viewModel.selectedArticle = upNext } label: {
                                FeaturedStory(article: upNext)
                            }
                            .buttonStyle(ArticleCardButtonStyle())
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .accessibilityHint("Opens the next piece in Queue")
                            .laterQueueActions(article: upNext, restore: restore, onChanged: { viewModel.reload() })
                        } header: {
                            GallerySectionHeader(text: upNext.contentKind == "youtube" ? "Up next · Video" : "Up next")
                        }
                    }

                    laterSection(title: "Videos", articles: videos)
                    laterSection(title: "Articles", articles: articles)
                    laterSection(title: "Listen", articles: audio)
                }
                .oneFeedGroupedListStyle()
            }
        }
        .navigationTitle("Queue")
        .oneFeedLargeTitle()
        .oneFeedPaperToolbar()
        .navigationSubtitle(waiting.isEmpty ? "" : waitingSubtitle)
        .background(OneFeedTheme.plaster)
        .oneFeedScrollEdge()
        .toolbar {
            ToolbarItem(placement: .oneFeedTrailing) {
                Button("Add", systemImage: "plus") { isAdding = true }
                    .accessibilityHint("Paste a link or pick a story from Feed")
            }
        }
        .task { viewModel.configure(with: modelContext) }
        .onAppear { viewModel.reload() }
        .sheet(isPresented: $isAdding, onDismiss: { viewModel.reload() }) {
            AddToQueueView { viewModel.reload() }
        }
        .oneFeedArticleCover(item: $viewModel.selectedArticle) { article in
            ReaderView(article: article) { state in
                viewModel.finishReading(article, as: state)
            }
            .onAppear { LibrarySyncService.shared.hasActiveReadingSession = true }
            .onDisappear { LibrarySyncService.shared.hasActiveReadingSession = false }
        }
        .alert("Couldn’t update article", isPresented: Binding(get: { viewModel.presentedError != nil }, set: { if !$0 { viewModel.presentedError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(viewModel.presentedError ?? "") }
    }

    @ViewBuilder
    private var empty: some View {
        EmptyLibraryState(
            title: "Nothing waiting",
            systemImage: "square.stack",
            description: "Park a story from Today, or paste a link to read later.",
            actionTitle: "Open Today",
            action: { NotificationCenter.default.post(name: OneFeedNotify.openToday, object: nil) },
            secondaryTitle: "Add a link",
            secondaryAction: { isAdding = true }
        )
    }

    private var waitingSubtitle: String {
        let videos = waiting.filter { $0.contentKind == "youtube" }.count
        let rest = waiting.count - videos
        if videos > 0, rest > 0 {
            return "\(waiting.count) in queue · \(videos) video\(videos == 1 ? "" : "s")"
        }
        if videos > 0 {
            return "\(videos) video\(videos == 1 ? "" : "s") in queue"
        }
        return "\(waiting.count) in queue"
    }

    private var videos: [Article] {
        rest.filter { $0.contentKind == "youtube" }
    }

    private var audio: [Article] {
        rest.filter { $0.contentKind == "podcast" || $0.contentKind == "music" }
    }

    private var articles: [Article] {
        rest.filter { $0.contentKind != "youtube" && $0.contentKind != "podcast" && $0.contentKind != "music" }
    }

    private var rest: [Article] {
        guard let upNext else { return waiting }
        return waiting.filter { $0.id != upNext.id }
    }

    @ViewBuilder
    private func laterSection(title: String, articles: [Article]) -> some View {
        if !articles.isEmpty {
            Section {
                ForEach(articles) { article in
                    laterRow(article)
                }
            } header: {
                GallerySectionHeader(text: title)
            }
        }
    }

    private func laterRow(_ article: Article) -> some View {
        Button {
            viewModel.selectedArticle = article
        } label: {
            QueueArticleRow(article: article)
                .padding(16)
        }
        .buttonStyle(ArticleCardButtonStyle())
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .accessibilityHint("Opens this piece from Queue")
        .laterQueueActions(article: article, restore: restore, onChanged: { viewModel.reload() })
    }

    private func restore(_ article: Article) {
        withAnimation(OneFeedMotion.list) {
            viewModel.restore(article)
        }
    }
}

private struct QueueArticleRow: View {
    let article: Article
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var imageFailed = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(article.title)
                    .font(.headline)
                    .foregroundStyle(OneFeedTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let source = article.feed?.title, !source.isEmpty {
                    Text(source)
                        .font(.subheadline)
                        .foregroundStyle(OneFeedTheme.graphite)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                }

                Text(details)
                    .font(.caption)
                    .foregroundStyle(OneFeedTheme.graphite)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let url = article.displayImageURL, !imageFailed, !dynamicTypeSize.isAccessibilitySize {
                ArticleThumbnail(url: url, cornerRadius: OneFeedTheme.radius) {
                    imageFailed = true
                }
                .frame(width: 64, height: 64)
            }
        }
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .combine)
        .onChange(of: article.imageURL) { _, _ in imageFailed = false }
    }

    private var details: String {
        var parts: [String] = []
        if let kind = article.kindLabel { parts.append(kind) }
        if let duration = article.timedDurationPhrase { parts.append(duration) }
        parts.append(article.publishedAt.formatted(.dateTime.month(.abbreviated).day()))
        if article.rating > 0 { parts.append(String(repeating: "★", count: article.rating)) }
        return parts.joined(separator: " · ")
    }
}

private struct LaterQueueActions: ViewModifier {
    let article: Article
    let restore: (Article) -> Void
    let onChanged: () -> Void
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button("Done", systemImage: "checkmark") {
                    ArticleActions.apply(.read, to: article, in: modelContext)
                    onChanged()
                }
                .tint(OneFeedTheme.sage)
                Button("Remove", systemImage: "arrow.uturn.backward") {
                    restore(article)
                }
                .tint(OneFeedTheme.stone)
            }
            .contextMenu {
                Button("Remove from Queue", systemImage: "arrow.uturn.backward") {
                    restore(article)
                }
                Button("Done", systemImage: "checkmark") {
                    ArticleActions.apply(.read, to: article, in: modelContext)
                    onChanged()
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

private extension View {
    func laterQueueActions(article: Article, restore: @escaping (Article) -> Void, onChanged: @escaping () -> Void) -> some View {
        modifier(LaterQueueActions(article: article, restore: restore, onChanged: onChanged))
    }
}
