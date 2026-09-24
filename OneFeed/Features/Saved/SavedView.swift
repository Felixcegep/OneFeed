import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SavedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(
        filter: #Predicate<Article> { $0.stateRawValue == "saved" },
        sort: \Article.completedAt,
        order: .reverse
    ) private var savedQuery: [Article]
    @State private var viewModel = SavedViewModel()
    @State private var isAdding = false
    @State private var appliedSearch = ""
    /// Collapsed queue stays put while the open story changes.
    @State private var queueCache = QueueListCache()

    private var waiting: [Article] {
        let stamp = queueStamp
        if queueCache.stamp == stamp { return queueCache.articles }
        let articles = ArticleIdentity.collapsingDuplicates(savedQuery).filter(\.isStored)
        queueCache.stamp = stamp
        queueCache.articles = articles
        return articles
    }

    private var queueStamp: Int {
        var hasher = Hasher()
        hasher.combine(savedQuery.count)
        for article in savedQuery {
            hasher.combine(article.id)
            hasher.combine(article.stateRawValue)
            hasher.combine(article.guid)
            hasher.combine(article.videoID)
            hasher.combine(article.url?.absoluteString)
        }
        return hasher.finalize()
    }

    private var searchQuery: String {
        appliedSearch.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// In-memory filter of `waiting`. An empty query returns the queue unchanged.
    private var visibleQueue: [Article] {
        let query = searchQuery
        guard !query.isEmpty else { return waiting }
        return waiting.filter { article in
            article.title.localizedStandardContains(query)
                || article.readingNote.localizedStandardContains(query)
                || (article.readingTakeawayLine?.localizedStandardContains(query) ?? false)
                || ArticlePresentation.sourceName(for: article).localizedStandardContains(query)
        }
    }

    private var upNext: Article? { visibleQueue.first }

    var body: some View {
        OneFeedReadingSplit(article: $viewModel.selectedArticle) {
            OneFeedSearchHost("Search queue", applied: $appliedSearch) {
                queueColumn
            }
        } reader: { article in
            ReaderView(article: article, onFinish: { state in
                viewModel.finishReading(article, as: state)
            }, onClose: {
                viewModel.selectedArticle = nil
            })
            .onAppear { LibrarySyncService.shared.hasActiveReadingSession = true }
            .onDisappear { LibrarySyncService.shared.hasActiveReadingSession = false }
        }
        .readingUndoBanner()
    }

    private var queueColumn: some View {
        Group {
            if waiting.isEmpty && searchQuery.isEmpty {
                empty
            } else if visibleQueue.isEmpty {
                noMatches
            } else {
                List {
                    if let upNext {
                        Section {
                            Button { viewModel.selectedArticle = upNext } label: {
                                FeaturedStory(article: upNext)
                            }
                            .buttonStyle(ArticleCardButtonStyle())
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .accessibilityHint("Opens the next piece in Queue")
                            .laterQueueActions(article: upNext, restore: restore, onChanged: {})
                        } header: {
                            GallerySectionHeader(
                                text: recentlySavedTitle(for: upNext)
                            )
                        }
                        #if os(iOS)
                        .listSectionSeparator(.hidden)
                        #endif
                    }

                    laterSection(title: "Videos", articles: videos)
                    laterSection(title: "Files", articles: files)
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
                    .accessibilityHint("Paste a link, import a file, or pick a story from Feed")
            }
            ToolbarItem(placement: .oneFeedTrailing) {
                NavigationLink {
                    HistoryView()
                } label: {
                    Label("History", systemImage: "clock")
                }
            }
        }
        .task {
            viewModel.configure(with: modelContext)
            openPendingImportedArticle()
        }
        .sheet(isPresented: $isAdding) {
            AddToQueueView {}
        }
        .onDrop(of: [.pdf, .epub, .url, .plainText], isTargeted: nil) { providers in
            importDropped(providers)
        }
        .onReceive(NotificationCenter.default.publisher(for: OneFeedNotify.addToQueue)) { note in
            if (note.userInfo?["pickFile"] as? Bool) == true { return }
            isAdding = true
        }
        .onReceive(NotificationCenter.default.publisher(for: OneFeedNotify.openQueueArticle)) { _ in
            openPendingImportedArticle()
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
            description: "Park a story from Today, or add a link or file to read later.",
            actionTitle: "Open Today",
            action: { NotificationCenter.default.post(name: OneFeedNotify.openToday, object: nil) },
            secondaryTitle: "Add to Queue",
            secondaryAction: { isAdding = true }
        )
    }

    @ViewBuilder
    private var noMatches: some View {
        EmptyLibraryState(
            title: "No matches",
            systemImage: "magnifyingglass",
            description: "Try a title, reading note, or source name."
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

    private var files: [Article] {
        rest.filter(\.isImportedDocument)
    }

    private var articles: [Article] {
        rest.filter { article in
            !article.isImportedDocument
                && article.contentKind != "youtube"
                && article.contentKind != "podcast"
                && article.contentKind != "music"
        }
    }

    private func recentlySavedTitle(for article: Article) -> String {
        switch article.contentKind {
        case "youtube": "Recently saved\u{00A0}·\u{00A0}Video"
        case "pdf": "Recently saved\u{00A0}·\u{00A0}PDF"
        case "epub": "Recently saved\u{00A0}·\u{00A0}Book"
        default: "Recently saved"
        }
    }

    private var rest: [Article] {
        guard let upNext else { return visibleQueue }
        return visibleQueue.filter { $0.id != upNext.id }
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
            #if os(iOS)
            .listSectionSeparator(.hidden)
            #endif
        }
    }

    private func laterRow(_ article: Article) -> some View {
        Button {
            viewModel.selectedArticle = article
        } label: {
            QueueArticleRow(article: article)
        }
        .buttonStyle(DirectoryRowButtonStyle())
        .articleListRow(isCurrent: article.isCurrentReading, isSelected: viewModel.selectedArticle?.id == article.id)
        .accessibilityHint("Opens this piece from Queue")
        .laterQueueActions(article: article, restore: restore, onChanged: {})
    }

    private func openPendingImportedArticle() {
        guard let id = QueueHandoff.pendingArticleID else { return }
        QueueHandoff.pendingArticleID = nil
        viewModel.openArticle(id: id)
    }

    private func restore(_ article: Article) {
        if reduceMotion {
            viewModel.restore(article)
        } else {
            withAnimation(OneFeedMotion.list) {
                viewModel.restore(article)
            }
        }
    }

    private func importDropped(_ providers: [NSItemProvider]) -> Bool {
        let files = providers.filter { provider in
            provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
                || provider.hasItemConformingToTypeIdentifier(UTType.epub.identifier)
        }
        if !files.isEmpty {
            Task {
                do {
                    let service = ImportedDocumentService()
                    var last: Article?
                    for provider in files {
                        let url = try await AddToQueueView.fileURLForDrop(from: provider)
                        last = try await service.importFile(at: url, in: modelContext)
                        try? FileManager.default.removeItem(at: url)
                    }
                    if let last { viewModel.selectedArticle = last }
                } catch {
                    viewModel.presentedError = UserFacingFailure.message(for: error, fallback: "Couldn’t import that file.")
                }
            }
            return true
        }

        let links = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
                || $0.canLoadObject(ofClass: URL.self)
                || $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }
        guard !links.isEmpty else { return false }
        Task {
            do {
                var last: Article?
                for provider in links {
                    guard let address = await Self.droppedAddress(from: provider) else { continue }
                    last = try await QueueLinkService().add(urlString: address, in: modelContext)
                }
                if let last { viewModel.selectedArticle = last }
            } catch {
                viewModel.presentedError = UserFacingFailure.message(for: error, fallback: "Couldn’t add that link.")
            }
        }
        return true
    }

    private static func droppedAddress(from provider: NSItemProvider) async -> String? {
        if provider.canLoadObject(ofClass: URL.self) {
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { object, _ in
                    continuation.resume(returning: object as? URL)
                }
            }
            if let url, !url.isFileURL { return url.absoluteString }
        }
        guard provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                continuation.resume(returning: item as? String)
            }
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
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)

                Group {
                    Text(ArticlePresentation.sourceName(for: article))
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
        .padding(.vertical, 4)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .combine)
        .onChange(of: article.imageURL) { _, _ in imageFailed = false }
    }

    private var details: String {
        var parts: [String] = []
        if let kind = article.kindLabel { parts.append(kind) }
        if let duration = article.timedDurationPhrase { parts.append(duration) }
        parts.append(OneFeedDateLabel.monthAndDay(article.publishedAt))
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
                Button("Not interested", systemImage: "hand.thumbsdown") {
                    ArticleActions.markNotInterested(article, in: modelContext)
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

private final class QueueListCache {
    var stamp = 0
    var articles: [Article] = []
}

private extension View {
    func laterQueueActions(article: Article, restore: @escaping (Article) -> Void, onChanged: @escaping () -> Void) -> some View {
        modifier(LaterQueueActions(article: article, restore: restore, onChanged: onChanged))
    }
}
