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
    @State private var isImportingDrop = false
    @State private var pendingDropProviders: [NSItemProvider] = []
    @State private var appliedSearch = ""
    /// Collapsed sections stay put while the open story changes. Rebuilt off the main thread when the queue or search changes.
    @State private var queueLayout = QueueLayout()
    @State private var queueReady = false

    /// Every waiting id and kind. Opening a story does not collapse the queue again.
    private var queueEdge: Int {
        var count = 0
        var mixed = 0
        for article in savedQuery {
            count += 1
            mixed = mixed &* 31 &+ article.id.hashValue
            mixed = mixed &* 31 &+ article.contentKind.hashValue
        }
        return count &* 31 &+ mixed
    }

    private var searchQuery: String {
        appliedSearch.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var queuePlanEdge: Int {
        var edge = queueEdge
        edge = edge &* 31 &+ appliedSearch.hashValue
        return edge
    }

    private func reloadQueue() async {
        let edge = queuePlanEdge
        let query = searchQuery
        let snaps = savedQuery.compactMap { article -> QueueStorySnap? in
            guard article.isStored else { return nil }
            return QueueStorySnap(
                id: article.id,
                publishedAt: article.publishedAt,
                title: article.title,
                readingNote: article.readingNote,
                reactionRaw: article.readingReactionRawValue,
                feedTitle: article.feed?.title,
                hasFeed: article.feed != nil,
                url: article.url,
                author: article.author,
                contentKind: article.contentKind,
                videoID: article.videoID,
                guid: article.guid,
                hasRemoteID: article.remoteID != nil,
                stateRaw: article.stateRawValue,
                isRemoteStarred: article.isRemoteStarred
            )
        }
        let plan = await Task.detached(priority: .userInitiated) {
            QueueListPlan.make(from: snaps, query: query)
        }.value
        guard !Task.isCancelled, edge == queuePlanEdge else { return }
        let byID = Dictionary(savedQuery.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let featuredArticle = plan.upNext.flatMap { byID[$0] }.flatMap { $0.isStored ? $0 : nil }
        let excerptSample = CardExcerptSample(
            aiSummary: ContentClassifier.cardExcerptSample(featuredArticle?.aiSummary),
            summary: ContentClassifier.cardExcerptSample(featuredArticle?.summary)
        )
        let excerpt = await Task.detached(priority: .userInitiated) {
            ContentClassifier.cardExcerpt(aiSummary: excerptSample.aiSummary, summary: excerptSample.summary)
        }.value
        guard !Task.isCancelled, edge == queuePlanEdge else { return }
        func articles(_ ids: [UUID]) -> [Article] {
            ids.compactMap { byID[$0] }.filter(\.isStored)
        }
        queueLayout = QueueLayout(
            upNext: featuredArticle,
            videos: articles(plan.videos),
            audio: articles(plan.audio),
            files: articles(plan.files),
            articles: articles(plan.articles),
            hasQueue: !plan.collapsedIDs.isEmpty,
            subtitle: plan.subtitle,
            upNextExcerpt: excerpt
        )
        queueReady = true
    }

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
        let layout = queueLayout
        return Group {
            if !queueReady && !layout.hasQueue {
                Color.clear
                    .frame(height: 1)
                    .accessibilityHidden(true)
            } else if queueReady && !layout.hasQueue && searchQuery.isEmpty {
                empty
            } else if queueReady && layout.upNext == nil && !searchQuery.isEmpty {
                noMatches
            } else {
                List {
                    if let upNext = layout.upNext {
                        Section {
                            Button { viewModel.selectedArticle = upNext } label: {
                                FeaturedStory(article: upNext, preparedExcerpt: layout.upNextExcerpt, usesPreparedExcerpt: true)
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

                    laterSection(title: "Videos", articles: layout.videos)
                    laterSection(title: "Files", articles: layout.files)
                    laterSection(title: "Articles", articles: layout.articles)
                    laterSection(title: "Listen", articles: layout.audio)
                }
                .oneFeedGroupedListStyle()
            }
        }
        .navigationTitle("Queue")
        .oneFeedLargeTitle()
        .oneFeedPaperToolbar()
        .navigationSubtitle(layout.hasQueue ? layout.subtitle : "")
        .task(id: queuePlanEdge) {
            await reloadQueue()
        }
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

    private func recentlySavedTitle(for article: Article) -> String {
        switch article.contentKind {
        case "youtube": "Recently saved\u{00A0}·\u{00A0}Video"
        case "pdf": "Recently saved\u{00A0}·\u{00A0}PDF"
        case "epub": "Recently saved\u{00A0}·\u{00A0}Book"
        default: "Recently saved"
        }
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
        let useful = providers.filter { provider in
            provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
                || provider.hasItemConformingToTypeIdentifier(UTType.epub.identifier)
                || provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
                || provider.canLoadObject(ofClass: URL.self)
                || provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }
        guard !useful.isEmpty else { return false }
        pendingDropProviders.append(contentsOf: useful)
        guard !isImportingDrop else { return true }
        isImportingDrop = true
        Task { await drainDroppedImports() }
        return true
    }

    private func drainDroppedImports() async {
        let service = ImportedDocumentService()
        var last: Article?
        while !pendingDropProviders.isEmpty {
            let batch = pendingDropProviders
            pendingDropProviders.removeAll()
            for provider in batch {
                let isFile = provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
                    || provider.hasItemConformingToTypeIdentifier(UTType.epub.identifier)
                do {
                    if isFile {
                        let url = try await AddToQueueView.fileURLForDrop(from: provider)
                        last = try await service.importFile(at: url, in: modelContext)
                        try? FileManager.default.removeItem(at: url)
                    } else if let address = await Self.droppedAddress(from: provider) {
                        last = try await QueueLinkService().add(urlString: address, in: modelContext)
                    }
                } catch {
                    let fallback = isFile ? "Couldn’t import that file." : "Couldn’t add that link."
                    viewModel.presentedError = UserFacingFailure.message(for: error, fallback: fallback)
                }
            }
        }
        if let last { viewModel.selectedArticle = last }
        isImportingDrop = false
        if !pendingDropProviders.isEmpty {
            isImportingDrop = true
            await drainDroppedImports()
        }
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

            if let url = article.displayImageURL, !dynamicTypeSize.isAccessibilitySize {
                if imageFailed {
                    RoundedRectangle(cornerRadius: OneFeedTheme.radius, style: .continuous)
                        .fill(OneFeedTheme.warm1)
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                } else {
                    ArticleThumbnail(url: url, cornerRadius: OneFeedTheme.radius) {
                        imageFailed = true
                    }
                    .frame(width: 64, height: 64)
                }
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
    @State private var ratingError: String?
    @State private var actionError: String?

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button("Done", systemImage: "checkmark") {
                    markDone()
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
                    markDone()
                }
                Button("Not interested", systemImage: "hand.thumbsdown") {
                    guard ArticleActions.markNotInterested(article, in: modelContext) else {
                        actionError = "Couldn’t file that as not interested."
                        return
                    }
                    onChanged()
                }
                Menu("Rate") {
                    ForEach(1...5, id: \.self) { stars in
                        Button {
                            saveRating(stars)
                        } label: {
                            Label(
                                "\(stars) star\(stars == 1 ? "" : "s")",
                                systemImage: article.rating >= stars ? "star.fill" : "star"
                            )
                        }
                    }
                    if article.rating > 0 {
                        Button("Clear rating", systemImage: "star.slash") {
                            saveRating(0)
                        }
                    }
                }
            }
            .alert("Couldn’t update that story", isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) {
                Button("OK", role: .cancel) { actionError = nil }
            } message: {
                Text(actionError ?? "")
            }
            .alert("Couldn’t save that rating", isPresented: Binding(
                get: { ratingError != nil },
                set: { if !$0 { ratingError = nil } }
            )) {
                Button("OK", role: .cancel) { ratingError = nil }
            } message: {
                Text(ratingError ?? "")
            }
    }

    private func markDone() {
        do {
            try ArticleActions.apply(.read, to: article, in: modelContext)
            onChanged()
        } catch {
            actionError = UserFacingFailure.message(for: error, fallback: "Couldn’t update that story.")
        }
    }

    private func saveRating(_ stars: Int) {
        do {
            try ArticleActions.rate(article, stars: stars, in: modelContext)
            onChanged()
        } catch {
            ratingError = UserFacingFailure.message(for: error, fallback: "Couldn’t save that rating.")
        }
    }
}

struct QueueStorySnap: Sendable {
    var id: UUID
    var publishedAt: Date
    var title: String
    var readingNote: String
    var reactionRaw: String
    var feedTitle: String?
    var hasFeed: Bool
    var url: URL?
    var author: String?
    var contentKind: String
    var videoID: String?
    var guid: String
    var hasRemoteID: Bool
    var stateRaw: String
    var isRemoteStarred: Bool
}

struct QueueSectionPlan: Sendable {
    var collapsedIDs: [UUID] = []
    var upNext: UUID?
    var videos: [UUID] = []
    var audio: [UUID] = []
    var files: [UUID] = []
    var articles: [UUID] = []
    var subtitle = ""
}

/// Same collapse and sections as the Queue screen, from copied fields.
nonisolated enum QueueListPlan {
    static func make(from stories: [QueueStorySnap], query: String) -> QueueSectionPlan {
        let collapsed = collapsedStories(stories)
        let visible = query.isEmpty ? collapsed : collapsed.filter { matches($0, query: query) }
        var plan = QueueSectionPlan(collapsedIDs: collapsed.map(\.id), subtitle: subtitle(for: collapsed))
        guard let featured = visible.first else { return plan }
        plan.upNext = featured.id
        for story in visible.dropFirst() {
            switch story.contentKind {
            case "youtube": plan.videos.append(story.id)
            case "podcast", "music": plan.audio.append(story.id)
            case "pdf", "epub": plan.files.append(story.id)
            default: plan.articles.append(story.id)
            }
        }
        return plan
    }

    private static func subtitle(for queue: [QueueStorySnap]) -> String {
        let videos = queue.reduce(into: 0) { count, story in
            if story.contentKind == "youtube" { count += 1 }
        }
        let rest = queue.count - videos
        if videos > 0, rest > 0 {
            return "\(queue.count) in queue · \(videos) video\(videos == 1 ? "" : "s")"
        }
        if videos > 0 {
            return "\(videos) video\(videos == 1 ? "" : "s") in queue"
        }
        return "\(queue.count) in queue"
    }

    private static func matches(_ story: QueueStorySnap, query: String) -> Bool {
        if story.title.localizedStandardContains(query) { return true }
        if story.readingNote.localizedStandardContains(query) { return true }
        if takeaway(story)?.localizedStandardContains(query) == true { return true }
        let source = ArticlePresentation.sourceName(
            feedTitle: story.feedTitle,
            url: story.url,
            author: story.author,
            contentKind: story.contentKind
        )
        return source.localizedStandardContains(query)
    }

    private static func takeaway(_ story: QueueStorySnap) -> String? {
        let note = story.readingNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = ArticleReadingReaction(stored: story.reactionRaw)?.label
        switch (label, note.isEmpty) {
        case (nil, true): return nil
        case let (label?, true): return label
        case (nil, false): return note
        case let (label?, false): return "\(label) \u{00B7} \(note)"
        }
    }

    private static func collapsedStories(_ stories: [QueueStorySnap]) -> [QueueStorySnap] {
        var order: [String] = []
        var groups: [String: [QueueStorySnap]] = [:]
        for story in stories {
            let key = identityKey(story)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(story)
        }
        return order.map { key in
            let items = groups[key] ?? []
            return items.max(by: { score($0) < score($1) }) ?? items[0]
        }
    }

    private static func identityKey(_ story: QueueStorySnap) -> String {
        if let videoID = story.videoID, !videoID.isEmpty { return "video:\(videoID)" }
        return ArticleIdentity.libraryKey(url: story.url, guid: story.guid, id: story.id)
    }

    private static func score(_ story: QueueStorySnap) -> Int {
        var value = 0
        if story.hasFeed { value += 8 }
        if story.hasRemoteID { value += 4 }
        if story.stateRaw == "saved" || story.isRemoteStarred { value += 3 }
        if story.stateRaw == "current" { value += 2 }
        return value
    }
}

private struct QueueLayout {
    var upNext: Article?
    var videos: [Article] = []
    var audio: [Article] = []
    var files: [Article] = []
    var articles: [Article] = []
    var hasQueue = false
    var subtitle = ""
    var upNextExcerpt: String?
}

private extension View {
    func laterQueueActions(article: Article, restore: @escaping (Article) -> Void, onChanged: @escaping () -> Void) -> some View {
        modifier(LaterQueueActions(article: article, restore: restore, onChanged: onChanged))
    }
}
