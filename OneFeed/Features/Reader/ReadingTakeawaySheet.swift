import SwiftData
import SwiftUI

struct ReadingTakeawaySheet: View {
    #if os(iOS)
    private enum TakeawaySavePurpose {
        case save
        case captureDraft
    }

    private struct DraftRefinement: Identifiable {
        let id: UUID
        let note: KnowledgeNote

        init(note: KnowledgeNote) {
            id = note.id
            self.note = note
        }
    }
    #endif

    let article: Article
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @Environment(\.modelContext) private var modelContext
    #endif
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reaction: ArticleReadingReaction?
    @State private var note: String
    @State private var selectionPulse = 0
    @State private var detent: PresentationDetent = .medium
    @State private var explicitDismiss = false
    @State private var didWrite = false
    @State private var showsFirstVisitHint = false
    #if os(iOS)
    @State private var draftSaveError: String?
    @State private var failedSavePurpose: TakeawaySavePurpose?
    @State private var isCreatingDraft = false
    @State private var lastCapturedDraftText: String?
    @State private var draftAwaitingConfirmation: KnowledgeNote?
    @State private var showingDraftSavedConfirmation = false
    @State private var draftToRefine: DraftRefinement?
    #endif
    @AppStorage(AppPreferenceKey.didSeeTakeawayHint) private var didSeeTakeawayHint = false
    @FocusState private var noteFocused: Bool

    init(article: Article) {
        self.article = article
        _reaction = State(initialValue: article.readingReaction)
        _note = State(initialValue: article.readingNoteText)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if showsFirstVisitHint {
                        Text("A sentence is optional. Not now still finishes the story.")
                            .font(.subheadline)
                            .foregroundStyle(OneFeedTheme.graphite)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    choices
                    Text(promptCopy)
                        .font(.subheadline)
                        .foregroundStyle(OneFeedTheme.graphite)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                        .animation(reduceMotion ? nil : OneFeedMotion.reveal, value: promptCopy)
                    TextField("", text: $note, prompt: Text("In your own words"), axis: .vertical)
                        .textFieldStyle(.plain)
                        .focused($noteFocused)
                        .lineLimit(2...4)
                        .font(OneFeedTheme.serifBody(17))
                        .foregroundStyle(OneFeedTheme.ink)
                        .padding(12)
                        .background(
                            OneFeedTheme.paper,
                            in: RoundedRectangle(cornerRadius: OneFeedTheme.radius, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: OneFeedTheme.radius, style: .continuous)
                                .strokeBorder(OneFeedTheme.sand, lineWidth: 1)
                        }
                        .accessibilityLabel(promptCopy)
                    #if os(iOS)
                    if !trimmedNote.isEmpty {
                        let alreadyCaptured = lastCapturedDraftText == trimmedNote
                        Button(
                            alreadyCaptured ? "Draft saved" : "Save as draft",
                            systemImage: alreadyCaptured ? "checkmark" : "square.and.pencil",
                            action: captureDraft
                        )
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .disabled(isCreatingDraft || alreadyCaptured)
                            .accessibilityHint("Saves this takeaway and keeps a rough draft with its source")
                    }
                    #endif
                }
                .padding(OneFeedTheme.pagePadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize)
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .background(OneFeedTheme.paper)
            .onChange(of: noteFocused) { _, focused in
                guard focused, !dynamicTypeSize.isAccessibilitySize else { return }
                withAnimation(reduceMotion ? nil : OneFeedMotion.reveal) {
                    detent = .large
                }
            }
            .navigationTitle("What stayed with you?")
            .oneFeedInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") {
                        explicitDismiss = true
                        dismiss()
                    }
                    .accessibilityHint("Marks this article read without a note")
                }
                ToolbarItem(placement: .confirmationAction) {
                    #if os(iOS)
                    Button("Save takeaway") { save() }
                    #else
                    Button("Save") { save() }
                    #endif
                }
            }
            #if os(iOS)
            .sheet(item: $draftToRefine) { draft in
                IdeaEditorSheet(note: draft.note)
            }
            .confirmationDialog("Draft saved", isPresented: $showingDraftSavedConfirmation, titleVisibility: .visible) {
                Button("Refine draft") {
                    if let draftAwaitingConfirmation {
                        draftToRefine = DraftRefinement(note: draftAwaitingConfirmation)
                    }
                    draftAwaitingConfirmation = nil
                }
                Button("Done", role: .cancel) {
                    draftAwaitingConfirmation = nil
                }
            } message: {
                Text("Your rough draft is saved with this source.")
            }
            .alert("Couldn’t save", isPresented: Binding(
                get: { draftSaveError != nil },
                set: { if !$0 { draftSaveError = nil } }
            )) {
                Button("Try again") { retryDraftAction() }
                Button("OK", role: .cancel) { draftSaveError = nil }
            } message: {
                Text(draftSaveError ?? "Your takeaway is still here. Try saving again.")
            }
            #endif
            .sensoryFeedback(.selection, trigger: selectionPulse)
            .onAppear {
                guard !didSeeTakeawayHint else { return }
                showsFirstVisitHint = true
                didSeeTakeawayHint = true
            }
            .onDisappear { keepDraftIfNeeded() }
        }
        .oneFeedMacFormSheet()
        #if os(iOS)
        .presentationDetents(
            dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large],
            selection: $detent
        )
        .presentationDragIndicator(.visible)
        .presentationBackground(OneFeedTheme.paper)
        #endif
    }

    private var promptCopy: String {
        reaction?.prompt ?? String(localized: "A sentence or two, in your own words.")
    }

    @ViewBuilder
    private var choices: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                choiceChips
            }
        } else {
            HStack(spacing: 8) {
                choiceChips
            }
        }
    }

    private var choiceChips: some View {
        ForEach(ArticleReadingReaction.allCases, id: \.self) { option in
            choiceChip(option)
        }
    }

    private func choiceChip(_ option: ArticleReadingReaction) -> some View {
        let selected = reaction == option
        return Button {
            let selecting = reaction != option
            withAnimation(reduceMotion ? nil : OneFeedMotion.press) {
                reaction = selecting ? option : nil
            }
            if selecting {
                selectionPulse += 1
            }
        } label: {
            VStack(spacing: 2) {
                Text(option.glyph)
                    .font(.title3)
                    .scaleEffect((!selected || reduceMotion) ? 1 : 1.08)
                    .animation(reduceMotion ? nil : OneFeedMotion.press, value: selected)
                    .accessibilityHidden(true)
                Text(option.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(selected ? OneFeedTheme.plaster : OneFeedTheme.ink)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                selected ? OneFeedTheme.ink : OneFeedTheme.paper,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(selected ? Color.clear : OneFeedTheme.sand, lineWidth: 1)
            }
        }
        .buttonStyle(ReadingChoicePressStyle())
        .frame(maxWidth: .infinity)
        .accessibilityLabel(option.label)
        .accessibilityHint(option.prompt)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var trimmedNote: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDirty: Bool {
        reaction != article.readingReaction || trimmedNote != article.readingNoteText
    }

    private func keepDraftIfNeeded() {
        guard !explicitDismiss, !didWrite, isDirty, article.isStored else { return }
        article.setReadingTakeaway(reaction: reaction, note: trimmedNote)
        LibraryChange.note(article)
        try? article.modelContext?.save()
        didWrite = true
    }

    private func save() {
        if reaction == nil, trimmedNote.isEmpty {
            explicitDismiss = true
            dismiss()
            return
        }
        #if os(iOS)
        guard persistTakeaway(for: .save) else { return }
        #else
        article.setReadingTakeaway(reaction: reaction, note: trimmedNote)
        if article.isStored {
            LibraryChange.note(article)
            try? article.modelContext?.save()
        }
        #endif
        didWrite = true
        dismiss()
    }

    #if os(iOS)
    private func captureDraft() {
        guard !trimmedNote.isEmpty, !isCreatingDraft else { return }
        isCreatingDraft = true
        guard persistTakeaway(for: .captureDraft) else {
            isCreatingDraft = false
            return
        }

        do {
            let draft = try KnowledgeNoteStore.create(
                title: "",
                explanation: "",
                article: article,
                isDraft: true,
                draftText: note,
                in: modelContext
            )
            lastCapturedDraftText = trimmedNote
            draftAwaitingConfirmation = draft
            showingDraftSavedConfirmation = true
        } catch {
            failedSavePurpose = .captureDraft
            draftSaveError = "Your takeaway is saved, but the draft could not be saved. Your text is still here. Try again."
        }
        isCreatingDraft = false
    }

    private func persistTakeaway(for purpose: TakeawaySavePurpose) -> Bool {
        guard article.isStored else {
            failedSavePurpose = purpose
            draftSaveError = "This source is no longer available to save. Your takeaway is still here."
            return false
        }

        let previousReaction = article.readingReactionRawValue
        let previousNote = article.readingNote
        let previousLibraryUpdatedAt = article.libraryUpdatedAt
        article.setReadingTakeaway(reaction: reaction, note: trimmedNote)
        article.touchLibrary()

        do {
            try modelContext.save()
        } catch {
            article.readingReactionRawValue = previousReaction
            article.readingNote = previousNote
            article.libraryUpdatedAt = previousLibraryUpdatedAt
            failedSavePurpose = purpose
            draftSaveError = "Your takeaway could not be saved. Your text is still here. Try again."
            return false
        }

        failedSavePurpose = nil
        draftSaveError = nil
        LibrarySyncService.shared.schedulePush()
        return true
    }

    private func retryDraftAction() {
        switch failedSavePurpose {
        case .some(.save):
            save()
        case .some(.captureDraft):
            captureDraft()
        case .none:
            draftSaveError = nil
        }
    }
    #endif
}

/// Plain chip with the same 0.97 press scale as `InkCapsuleStyle`.
private struct ReadingChoicePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect((reduceMotion || !configuration.isPressed) ? 1 : 0.97)
            .animation(reduceMotion ? nil : OneFeedMotion.press, value: configuration.isPressed)
    }
}
