import SwiftData
import SwiftUI

struct ReadingTakeawaySheet: View {
    let article: Article
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reaction: ArticleReadingReaction?
    @State private var note: String
    @State private var selectionPulse = 0
    @State private var detent: PresentationDetent = .medium
    @State private var explicitDismiss = false
    @State private var didWrite = false
    @State private var showsFirstVisitHint = false
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
                        .oneFeedLegibleWeight()
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
                    Button("Save") { save() }
                }
            }
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
        guard !didWrite, !explicitDismiss else { return }
        if reaction == nil, trimmedNote.isEmpty {
            explicitDismiss = true
            dismiss()
            return
        }
        article.setReadingTakeaway(reaction: reaction, note: trimmedNote)
        if article.isStored {
            LibraryChange.note(article)
            try? article.modelContext?.save()
        }
        didWrite = true
        dismiss()
    }
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
