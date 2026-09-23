import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct AddToQueueView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Article> { $0.stateRawValue == "queued" || $0.stateRawValue == "current" },
        sort: \Article.publishedAt,
        order: .reverse
    ) private var unread: [Article]
    @State private var address = ""
    @State private var isAdding = false
    @State private var presentedError: String?
    @State private var isPickingFile = false
    #if os(iOS)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var sheetDetent: PresentationDetent = .large
    #endif
    var startWithFilePicker = false
    var onAdded: () -> Void

    private var suggestions: [Article] {
        Array(unread.filter(\.isStored).prefix(8))
    }

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
                    presentedError = error.localizedDescription
                }
            }
            .onDrop(of: [.pdf, .epub], isTargeted: nil) { providers in
                importDropped(providers)
            }
            .onAppear {
                if startWithFilePicker {
                    isPickingFile = true
                }
            }
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
                onAdded()
                dismiss()
            } catch {
                presentedError = error.localizedDescription
                isAdding = false
            }
        }
    }

    private func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty, !isAdding else { return }
        isAdding = true
        presentedError = nil
        Task {
            do {
                let service = ImportedDocumentService()
                for url in urls {
                    _ = try await service.importFile(at: url, in: modelContext)
                }
                onAdded()
                dismiss()
            } catch {
                presentedError = error.localizedDescription
                isAdding = false
            }
        }
    }

    private func importDropped(_ providers: [NSItemProvider]) -> Bool {
        let matching = providers.filter { provider in
            provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
                || provider.hasItemConformingToTypeIdentifier(UTType.epub.identifier)
        }
        guard !matching.isEmpty, !isAdding else { return false }
        isAdding = true
        presentedError = nil
        Task {
            do {
                let service = ImportedDocumentService()
                for provider in matching {
                    let url = try await Self.fileURLForDrop(from: provider)
                    _ = try await service.importFile(at: url, in: modelContext)
                    try? FileManager.default.removeItem(at: url)
                }
                onAdded()
                dismiss()
            } catch {
                presentedError = error.localizedDescription
                isAdding = false
            }
        }
        return true
    }

    private func addExisting(_ article: Article) {
        guard !isAdding else { return }
        isAdding = true
        do {
            try QueueLinkService().park(article, in: modelContext)
            onAdded()
            dismiss()
        } catch {
            presentedError = error.localizedDescription
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
