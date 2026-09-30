#if os(iOS)
import SwiftData
import SwiftUI

struct IdeaEditorSheet: View {
    let note: KnowledgeNote?
    let sourceArticle: Article?
    let onSave: ((KnowledgeNote) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var title: String
    @State private var draftText: String
    @State private var explanation: String
    @State private var formattedExplanation: Data?
    @State private var sourceReferencesText: String
    private let initialTitle: String
    private let initialDraftText: String
    private let initialExplanation: String
    private let initialFormattedExplanation: Data?
    private let initialSourceReferencesText: String
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case title
        case capture
        case explanation
        case sources
    }

    init(
        note: KnowledgeNote? = nil,
        sourceArticle: Article? = nil,
        initialExplanation: String = "",
        onSave: ((KnowledgeNote) -> Void)? = nil
    ) {
        self.note = note
        self.sourceArticle = sourceArticle
        self.onSave = onSave
        let startingTitle = note?.isDraft == true && note?.title == "Untitled draft" ? "" : (note?.title ?? "")
        let startingDraftText = note?.draftText ?? initialExplanation
        let startingExplanation = note?.explanation ?? ""
        let startingFormattedExplanation = note?.formattedExplanation
        let startingSourceReferencesText = note?.sourceReferences.joined(separator: "\n") ?? ""
        initialTitle = startingTitle
        initialDraftText = startingDraftText
        self.initialExplanation = startingExplanation
        initialFormattedExplanation = startingFormattedExplanation
        initialSourceReferencesText = startingSourceReferencesText
        _title = State(initialValue: startingTitle)
        _draftText = State(initialValue: startingDraftText)
        _explanation = State(initialValue: startingExplanation)
        _formattedExplanation = State(initialValue: startingFormattedExplanation)
        _sourceReferencesText = State(initialValue: startingSourceReferencesText)
    }

    private var isCaptureOnly: Bool { note == nil }
    private var isDraft: Bool { note?.isDraft ?? true }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedDraftText: String { draftText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedExplanation: String { explanation.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var sourceReferenceLines: [String] {
        sourceReferencesText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var hasUnsavedChanges: Bool {
        title != initialTitle
            || draftText != initialDraftText
            || explanation != initialExplanation
            || formattedExplanation != initialFormattedExplanation
            || sourceReferencesText != initialSourceReferencesText
    }

    private var titlePrompt: String {
        isCaptureOnly ? "Add a title (optional)" : "A clear title helps you find this later"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if isCaptureOnly {
                        captureComposer
                    } else {
                        refinementComposer
                    }

                    if let note, !note.draftText.isEmpty {
                        originalCapture(note.draftText)
                    }

                    sourceEditor

                    if isDraft, !isCaptureOnly {
                        Button(action: finishNote) {
                            Text("Finish note")
                        }
                        .buttonStyle(PrimaryActionStyle())
                        .disabled(isSaving)
                        .padding(.top, 2)
                    }
                }
                .padding(.horizontal, OneFeedTheme.pagePadding)
                .padding(.top, 22)
                .padding(.bottom, 40)
                .frame(maxWidth: OneFeedTheme.readingColumnWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .background(OneFeedTheme.paper)
            .navigationTitle(navigationTitle)
            .oneFeedInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isCaptureOnly || isDraft {
                        Button("Save draft", action: saveDraft)
                            .disabled(isSaving)
                    } else {
                        Button("Save", action: saveFinishedNote)
                            .disabled(isSaving)
                    }
                }
            }
            .alert("Couldn’t save your note", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Your changes are still here. Please try again.")
            }
        }
        .interactiveDismissDisabled(hasUnsavedChanges)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(OneFeedTheme.paper)
    }

    private var navigationTitle: String {
        if isCaptureOnly { return "Capture draft" }
        return isDraft ? "Refine draft" : "Edit note"
    }

    private var captureComposer: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("A rough note is enough. You can shape it later.")
                .font(.subheadline)
                .foregroundStyle(OneFeedTheme.graphite)
                .fixedSize(horizontal: false, vertical: true)

            TextField(titlePrompt, text: $title, axis: .vertical)
                .font(.system(.title2, design: .serif))
                .foregroundStyle(OneFeedTheme.ink)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2...5 : 1...3)
                .focused($focusedField, equals: .title)
                .accessibilityLabel("Optional draft title")

            VStack(alignment: .leading, spacing: 8) {
                GalleryLabel(text: "Rough note")
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $draftText)
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(OneFeedTheme.ink)
                        .scrollContentBackground(.hidden)
                        .focused($focusedField, equals: .capture)
                        .frame(minHeight: 260)
                        .accessibilityLabel("Rough note")
                        .accessibilityHint("Capture the thought as it is. You can refine it later.")

                    if trimmedDraftText.isEmpty {
                        Text("Capture the thought before it slips away…")
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(OneFeedTheme.graphite.opacity(0.8))
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    private var refinementComposer: some View {
        VStack(alignment: .leading, spacing: 20) {
            if isDraft {
                Text("Rewrite the thought in a way you’ll understand later.")
                    .font(.subheadline)
                    .foregroundStyle(OneFeedTheme.graphite)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField(titlePrompt, text: $title, axis: .vertical)
                .font(.system(.largeTitle, design: .serif))
                .foregroundStyle(OneFeedTheme.ink)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2...5 : 1...3)
                .focused($focusedField, equals: .title)
                .accessibilityLabel("Note title")

            VStack(alignment: .leading, spacing: 8) {
                GalleryLabel(text: isDraft ? "Your rewritten note" : "Your note")
                RichNoteEditor(text: $explanation, formattedText: $formattedExplanation)
                    .frame(minHeight: 320)
                    .accessibilityLabel("Your rewritten note")
                    .accessibilityHint("Rewrite the rough capture in your own words")
            }
        }
    }

    private func originalCapture(_ rawText: String) -> some View {
        DisclosureGroup("Original capture") {
            Text(rawText)
                .font(.system(.body, design: .serif))
                .foregroundStyle(OneFeedTheme.graphite)
                .lineSpacing(4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(OneFeedTheme.graphite)
    }

    private var sourceEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            GallerySectionHeader(text: "Sources")

            if let note, !note.sourceTitle.isEmpty {
                IdeaSourceCitationView(note: note)
            } else if let sourceArticle {
                IdeaSourceCitationView(article: sourceArticle)
            }

            TextField("https://… (one per line)", text: $sourceReferencesText, axis: .vertical)
                .font(.system(.body, design: .default))
                .foregroundStyle(OneFeedTheme.ink)
                .lineLimit(2...5)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .focused($focusedField, equals: .sources)
                .padding(12)
                .background(
                    OneFeedTheme.paper,
                    in: RoundedRectangle(cornerRadius: OneFeedTheme.radius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: OneFeedTheme.radius, style: .continuous)
                        .strokeBorder(OneFeedTheme.sand, lineWidth: 1)
                }
                .accessibilityLabel("Additional sources")
                .accessibilityHint("Enter one HTTP or HTTPS address per line")

            Text(isDraft ? "Add source links when you have them. A note needs at least one source to be finished." : "One web address per line.")
                .font(.footnote)
                .foregroundStyle(OneFeedTheme.graphite)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func saveDraft() {
        guard !isSaving else { return }
        if isCaptureOnly && trimmedDraftText.isEmpty {
            focusedField = .capture
            errorMessage = "Add a rough note before saving this draft."
            return
        }

        isSaving = true
        do {
            let savedNote: KnowledgeNote
            if let note {
                try KnowledgeNoteStore.update(
                    note,
                    title: title,
                    explanation: explanation,
                    formattedExplanation: formattedExplanation,
                    isDraft: true,
                    draftText: note.draftText,
                    sourceReferences: sourceReferenceLines,
                    in: modelContext
                )
                savedNote = note
            } else {
                savedNote = try KnowledgeNoteStore.create(
                    title: title,
                    explanation: "",
                    article: sourceArticle,
                    isDraft: true,
                    draftText: draftText,
                    sourceReferences: sourceReferenceLines,
                    in: modelContext
                )
            }
            onSave?(savedNote)
            dismiss()
        } catch {
            isSaving = false
            errorMessage = "Your draft couldn’t be saved. Your changes are still here. Please try again."
        }
    }

    private func finishNote() {
        guard !isSaving else { return }
        guard !trimmedTitle.isEmpty else {
            focusedField = .title
            errorMessage = "Add a title before finishing this note."
            return
        }
        guard !trimmedExplanation.isEmpty else {
            focusedField = .explanation
            errorMessage = "Write your explanation in your own words before finishing."
            return
        }
        guard hasAtLeastOneSource else {
            focusedField = .sources
            errorMessage = "Add at least one source before finishing this note."
            return
        }
        guard allSourceReferencesAreValid else {
            focusedField = .sources
            errorMessage = "Each source must be an HTTP or HTTPS address with a host."
            return
        }
        guard let note else { return }

        isSaving = true
        do {
            try KnowledgeNoteStore.update(
                note,
                title: trimmedTitle,
                explanation: explanation,
                formattedExplanation: formattedExplanation,
                isDraft: false,
                draftText: note.draftText,
                sourceReferences: sourceReferenceLines,
                in: modelContext
            )
            onSave?(note)
            dismiss()
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
        }
    }

    private func saveFinishedNote() {
        guard !isSaving else { return }
        guard !trimmedTitle.isEmpty else {
            focusedField = .title
            errorMessage = "Add a title before saving this note."
            return
        }
        guard !trimmedExplanation.isEmpty else {
            errorMessage = "Write your explanation in your own words before saving."
            return
        }
        guard hasAtLeastOneSource else {
            focusedField = .sources
            errorMessage = "Add at least one source before saving this note."
            return
        }
        guard allSourceReferencesAreValid else {
            focusedField = .sources
            errorMessage = "Each source must be an HTTP or HTTPS address with a host."
            return
        }
        guard let note else { return }
        isSaving = true
        do {
            try KnowledgeNoteStore.update(
                note,
                title: trimmedTitle,
                explanation: explanation,
                formattedExplanation: formattedExplanation,
                sourceReferences: sourceReferenceLines,
                in: modelContext
            )
            onSave?(note)
            dismiss()
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
        }
    }

    private var allSourceReferencesAreValid: Bool {
        sourceReferenceLines.allSatisfy { rawValue in
            guard let components = URLComponents(string: rawValue),
                  let scheme = components.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let host = components.host else { return false }
            return !host.isEmpty && components.url != nil
        }
    }

    private var hasAtLeastOneSource: Bool {
        let primaryURL = note?.sourceURL ?? sourceArticle.flatMap { article in
            if article.contentKind == "youtube",
               let videoID = article.videoID,
               let videoURL = YouTubeProcessor.watchURL(for: videoID) {
                return videoURL
            }
            return article.url
        }
        let hasPrimaryWebURL: Bool = {
            guard let primaryURL,
                  let scheme = primaryURL.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let host = primaryURL.host else { return false }
            return !host.isEmpty
        }()
        let hasArticleAttribution = note.map {
            $0.sourceArticleID != nil
                && !$0.sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? false
        let hasCurrentArticleAttribution = sourceArticle.map { !$0.title.isEmpty } ?? false
        return hasPrimaryWebURL
            || hasArticleAttribution
            || hasCurrentArticleAttribution
            || sourceReferenceLines.contains(where: isValidWebURL)
    }

    private func isValidWebURL(_ rawValue: String) -> Bool {
        guard let components = URLComponents(string: rawValue),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host else { return false }
        return !host.isEmpty && components.url != nil
    }
}
#endif
