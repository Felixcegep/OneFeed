import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct AddToQueueView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    /// Eight Feed stories. Loaded without article bodies so opening the sheet does not read the library.
    @State private var suggestions: [Article] = []
    @State private var address = ""
    @State private var isAdding = false
    @State private var pendingFileURLs: [URL] = []
    @State private var pendingDropProviders: [NSItemProvider] = []
    @State private var presentedError: String?
    /// False once the sheet is gone, so a finished import does not dismiss the next screen.
    @State private var stillPresented = true
    @State private var isPickingFile = false
    #if os(iOS)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var sheetDetent: PresentationDetent = .large
    #endif
    var startWithFilePicker = false
    var onAdded: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://", text: $address, axis: .vertical)
                        .textContentType(.URL)
                        .oneFeedURLKeyboard()
                        .oneFeedAutocapitalizationNever()
                        .autocorrectionDisabled()
                        .lineLimit(2...4)
                        .oneFeedSubmitGo()
                    .onSubmit { addLink() }
                    .listRowBackground(OneFeedTheme.paper)
                    Button {
                        pasteCopiedLink()
                    } label: {
                        Label("Paste copied link", systemImage: "doc.on.clipboard")
                    }
                    .accessibilityHint("Reads the clipboard only after you tap")
                    .listRowBackground(OneFeedTheme.paper)
                } header: {
                    GallerySectionHeader(text: "Link")
                } footer: {
                    Text("Paste an article, YouTube, PDF, or EPUB URL.")
                        .foregroundStyle(OneFeedTheme.graphite)
                }

                Section {
                    Button {
                        isPickingFile = true
                    } label: {
                        Label("Import EPUB or PDF", systemImage: "doc.badge.plus")
                    }
                    .disabled(isAdding)
                    .accessibilityHint("Opens the file picker")
                    .listRowBackground(OneFeedTheme.paper)
                } header: {
                    GallerySectionHeader(text: "File")
                } footer: {
                    Text("Books and papers go into Queue. They stay on this device.")
                        .foregroundStyle(OneFeedTheme.graphite)
                }

                if let presentedError {
                    Section {
                        Text(presentedError).foregroundStyle(OneFeedTheme.error)
                            .listRowBackground(OneFeedTheme.paper)
                    }
                }

                if !suggestions.isEmpty {
                    Section {
                        ForEach(suggestions) { article in
                            Button {
                                addExisting(article)
                            } label: {
                                ArticleRow(article: article)
                            }
                            .accessibilityHint("Adds this to Queue")
                            .articleListRow(isCurrent: article.isCurrentReading)
                        }
                    } header: {
                        GallerySectionHeader(text: "From Feed")
                    } footer: {
                        Text("One tap adds it to Queue.")
                            .foregroundStyle(OneFeedTheme.graphite)
                    }
                }
            }
            .navigationTitle("Add to Queue")
            .oneFeedInlineTitle()
            .oneFeedPaperScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isAdding)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isAdding ? "Adding…" : "Add") { addLink() }
                        .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAdding)
                }
            }
            .interactiveDismissDisabled(isAdding)
            .fileImporter(
                isPresented: $isPickingFile,
                allowedContentTypes: ImportedDocumentKind.readableTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    importFiles(urls)
                case .failure(let error):
                    presentedError = UserFacingFailure.message(for: error, fallback: "Couldn’t add that to Queue.")
                }
            }
            .onDrop(of: [.pdf, .epub], isTargeted: nil) { providers in
                importDropped(providers)
            }
            .task {
                let container = modelContext.container
                let ids = await Task.detached(priority: .userInitiated) {
                    QueueFeedSuggestions.ids(in: container)
                }.value
                guard !Task.isCancelled else { return }
                suggestions = QueueFeedSuggestions.stories(for: ids, in: modelContext)
            }
            .onAppear {
                if startWithFilePicker {
                    isPickingFile = true
                }
            }
            .onDisappear { stillPresented = false }
        }
        .oneFeedMacFormSheet()
        #if os(iOS)
        .presentationDetents(
            dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large],
            selection: $sheetDetent
        )
        #endif
    }

    private func pasteCopiedLink() {
        guard let url = QueueLinkService.pasteboardURL else {
            presentedError = "No link on the clipboard."
            return
        }
        address = url.absoluteString
        addLink()
    }

    private func addLink() {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !isAdding else { return }
        isAdding = true
        presentedError = nil
        Task {
            do {
                _ = try await QueueLinkService().add(urlString: value, in: modelContext)
            } catch {
                presentedError = UserFacingFailure.message(for: error, fallback: "Couldn’t add that to Queue.")
            }
            await completeAdd()
        }
    }

    private func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        pendingFileURLs.append(contentsOf: urls)
        beginAdd()
    }

    private func importDropped(_ providers: [NSItemProvider]) -> Bool {
        let matching = providers.filter { provider in
            provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
                || provider.hasItemConformingToTypeIdentifier(UTType.epub.identifier)
        }
        guard !matching.isEmpty else { return false }
        pendingDropProviders.append(contentsOf: matching)
        beginAdd()
        return true
    }

    private func beginAdd() {
        guard !isAdding else { return }
        isAdding = true
        presentedError = nil
        Task { await completeAdd() }
    }

    private func completeAdd() async {
        let service = ImportedDocumentService()
        var succeeded = 0
        var failed = 0
        var firstFailure: String?
        while !pendingFileURLs.isEmpty || !pendingDropProviders.isEmpty {
            let urls = pendingFileURLs
            pendingFileURLs.removeAll()
            let drops = pendingDropProviders
            pendingDropProviders.removeAll()
            for url in urls {
                do {
                    _ = try await service.importFile(at: url, in: modelContext)
                    succeeded += 1
                } catch {
                    failed += 1
                    if firstFailure == nil {
                        firstFailure = UserFacingFailure.message(for: error, fallback: "Couldn’t add that to Queue.")
                    }
                }
            }
            for provider in drops {
                do {
                    let url = try await Self.fileURLForDrop(from: provider)
                    _ = try await service.importFile(at: url, in: modelContext)
                    try? FileManager.default.removeItem(at: url)
                    succeeded += 1
                } catch {
                    failed += 1
                    if firstFailure == nil {
                        firstFailure = UserFacingFailure.message(for: error, fallback: "Couldn’t add that to Queue.")
                    }
                }
            }
        }
        if let batchError = ImportBatchResult.message(
            succeeded: succeeded,
            failed: failed,
            firstFailure: firstFailure,
            emptyFallback: "Couldn’t add that to Queue."
        ) {
            presentedError = batchError
        }
        if presentedError == nil || succeeded > 0 {
            onAdded()
        }
        if presentedError == nil {
            guard stillPresented else { return }
            dismiss()
        } else {
            isAdding = false
        }
    }

    private func addExisting(_ article: Article) {
        guard !isAdding else { return }
        isAdding = true
        do {
            try QueueLinkService().park(article, in: modelContext)
            onAdded()
            dismiss()
        } catch {
            presentedError = UserFacingFailure.message(for: error, fallback: "Couldn’t add that to Queue.")
            isAdding = false
        }
    }

    static func fileURLForDrop(from provider: NSItemProvider) async throws -> URL {
        let type = provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
            ? UTType.pdf.identifier
            : UTType.epub.identifier
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: ImportedDocumentError.unreadable)
                    return
                }
                let destination = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + "-" + url.lastPathComponent)
                do {
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// The eight newest open stories for Add to Queue. The fetch stops early and leaves article bodies on disk.
enum QueueFeedSuggestions {
    static let shown = 8
    static let fetchCap = 24

    /// Chooses suggestion ids away from the open sheet. The sheet then fetches only those rows.
    static func ids(in container: ModelContainer) -> [UUID] {
        let lookup = ModelContext(container)
        lookup.autosaveEnabled = false
        let queued = ArticleState.queued.rawValue
        let current = ArticleState.current.rawValue
        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { article in
                article.stateRawValue == queued || article.stateRawValue == current
            },
            sortBy: [SortDescriptor(\.publishedAt, order: .reverse)]
        )
        descriptor.fetchLimit = fetchCap
        descriptor.propertiesToFetch = [\.id, \.url, \.videoID, \.guid, \.remoteID, \.stateRawValue, \.isRemoteStarred]
        descriptor.relationshipKeyPathsForPrefetching = [\.feed]
        let fetched = (try? lookup.fetch(descriptor)) ?? []
        let snaps = fetched.filter(\.isStored).map {
            QueueSuggestionSnap(
                id: $0.id,
                url: $0.url,
                videoID: $0.videoID,
                guid: $0.guid,
                hasFeed: $0.feed != nil,
                hasRemoteID: $0.remoteID != nil,
                stateRaw: $0.stateRawValue,
                isRemoteStarred: $0.isRemoteStarred
            )
        }
        return chosenIDs(from: snaps)
    }

    static func stories(for ids: [UUID], in context: ModelContext) -> [Article] {
        guard !ids.isEmpty else { return [] }
        let needed = ids
        let fetched = (try? context.fetch(ArticleListFetch.rows(
            predicate: #Predicate { needed.contains($0.id) }
        ))) ?? []
        let byID = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    static func chosenIDs(from snaps: [QueueSuggestionSnap]) -> [UUID] {
        var order: [String] = []
        var groups: [String: [QueueSuggestionSnap]] = [:]
        for snap in snaps {
            let key = identityKey(snap)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(snap)
        }
        return order.prefix(shown).map { key in
            let items = groups[key] ?? []
            return items.max(by: { score($0) < score($1) })?.id ?? items[0].id
        }
    }

    static func capped(_ articles: [Article]) -> [Article] {
        let ids = chosenIDs(from: articles.map(QueueSuggestionSnap.init))
        let byID = Dictionary(articles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    private static func identityKey(_ snap: QueueSuggestionSnap) -> String {
        if let videoID = snap.videoID, !videoID.isEmpty { return "video:\(videoID)" }
        return ArticleIdentity.libraryKey(url: snap.url, guid: snap.guid, id: snap.id)
    }

    private static func score(_ snap: QueueSuggestionSnap) -> Int {
        var value = 0
        if snap.hasFeed { value += 8 }
        if snap.hasRemoteID { value += 4 }
        if snap.stateRaw == ArticleState.saved.rawValue || snap.isRemoteStarred { value += 3 }
        if snap.stateRaw == ArticleState.current.rawValue { value += 2 }
        return value
    }
}

struct QueueSuggestionSnap: Sendable {
    var id: UUID
    var url: URL?
    var videoID: String?
    var guid: String
    var hasFeed: Bool
    var hasRemoteID: Bool
    var stateRaw: String
    var isRemoteStarred: Bool

    init(id: UUID, url: URL?, videoID: String?, guid: String, hasFeed: Bool, hasRemoteID: Bool, stateRaw: String, isRemoteStarred: Bool) {
        self.id = id
        self.url = url
        self.videoID = videoID
        self.guid = guid
        self.hasFeed = hasFeed
        self.hasRemoteID = hasRemoteID
        self.stateRaw = stateRaw
        self.isRemoteStarred = isRemoteStarred
    }

    init(_ article: Article) {
        self.init(
            id: article.id,
            url: article.url,
            videoID: article.videoID,
            guid: article.guid,
            hasFeed: article.feed != nil,
            hasRemoteID: article.remoteID != nil,
            stateRaw: article.stateRawValue,
            isRemoteStarred: article.isRemoteStarred
        )
    }
}
