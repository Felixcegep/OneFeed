import SwiftData
import SwiftUI

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
    #if os(iOS)
    @State private var sheetDetent: PresentationDetent = .large
    #endif
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
                    Text("Paste an article or YouTube URL. That’s it.")
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
                            .articleListRow()
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
        }
        .oneFeedMacFormSheet()
        #if os(iOS)
        .presentationDetents([.medium, .large], selection: $sheetDetent)
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
}
