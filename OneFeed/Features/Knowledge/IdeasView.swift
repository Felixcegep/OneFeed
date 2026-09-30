#if os(iOS)
import SwiftData
import SwiftUI

struct IdeasView: View {
    @Query(
        filter: #Predicate<KnowledgeNote> { $0.deletedAt == nil },
        sort: \KnowledgeNote.updatedAt,
        order: .reverse
    ) private var notes: [KnowledgeNote]
    @State private var searchText = ""
    @State private var isPresentingEditor = false

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleNotes: [KnowledgeNote] {
        guard !query.isEmpty else { return notes }
        return notes.filter { note in
            note.title.localizedCaseInsensitiveContains(query)
                || note.explanation.localizedCaseInsensitiveContains(query)
                || note.draftText.localizedCaseInsensitiveContains(query)
                || note.sourceTitle.localizedCaseInsensitiveContains(query)
                || note.sourceReferences.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    private var visibleDrafts: [KnowledgeNote] { visibleNotes.filter(\.isDraft) }
    private var visibleFinishedNotes: [KnowledgeNote] { visibleNotes.filter { !$0.isDraft } }

    var body: some View {
        Group {
            if notes.isEmpty {
                EmptyLibraryState(
                    title: "Capture an idea as it comes",
                    systemImage: "lightbulb",
                    description: "Save a rough thought now. Refine it into a sourced note when you’re ready.",
                    actionTitle: "Capture draft",
                    action: { isPresentingEditor = true }
                )
            } else if visibleNotes.isEmpty {
                EmptyLibraryState(
                    title: "No matches",
                    systemImage: "magnifyingglass",
                    description: "Try a different title, explanation, or source name.",
                    actionTitle: "Clear search",
                    action: { searchText = "" }
                )
            } else {
                List {
                    if !visibleDrafts.isEmpty {
                        Section {
                            ForEach(visibleDrafts) { note in
                                NavigationLink {
                                    IdeaDetailView(note: note)
                                } label: {
                                    IdeaRow(note: note)
                                }
                                .buttonStyle(DirectoryRowButtonStyle())
                                .listRowBackground(OneFeedTheme.paper)
                            }
                        } header: {
                            GallerySectionHeader(text: "Drafts")
                        }
                    }

                    if !visibleFinishedNotes.isEmpty {
                        Section {
                            ForEach(visibleFinishedNotes) { note in
                                NavigationLink {
                                    IdeaDetailView(note: note)
                                } label: {
                                    IdeaRow(note: note)
                                }
                                .buttonStyle(DirectoryRowButtonStyle())
                                .listRowBackground(OneFeedTheme.paper)
                            }
                        } header: {
                            GallerySectionHeader(text: "Notes")
                        }
                    }
                }
                .oneFeedGroupedListStyle()
            }
        }
        .navigationTitle("Ideas")
        .oneFeedInlineTitle()
        .oneFeedPaperToolbar()
        .background(OneFeedTheme.plaster)
        .oneFeedSearchable($searchText, prompt: "Search ideas")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingEditor = true
                } label: {
                    Label("Capture draft", systemImage: "plus")
                }
                .accessibilityHint("Save a rough thought to refine later")
            }
        }
        .sheet(isPresented: $isPresentingEditor) {
            IdeaEditorSheet()
        }
    }
}

struct IdeaRow: View {
    let note: KnowledgeNote
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(displayTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(OneFeedTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if note.isDraft {
                    Text("Draft")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(OneFeedTheme.graphite)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(OneFeedTheme.paper, in: Capsule())
                        .overlay { Capsule().strokeBorder(OneFeedTheme.sand, lineWidth: 1) }
                        .fixedSize()
                }
            }

            Text(rowText)
                .font(.system(.body, design: .serif))
                .foregroundStyle(OneFeedTheme.graphite)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            if !note.sourceTitle.isEmpty || note.sourceURL != nil {
                Label(note.sourceTitle.isEmpty ? (note.sourceURL?.host ?? "Source") : note.sourceTitle, systemImage: "text.quote")
                    .font(.subheadline)
                    .foregroundStyle(OneFeedTheme.graphite)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !note.sourceReferences.isEmpty {
                Label(note.sourceReferences.count == 1 ? "1 source" : "\(note.sourceReferences.count) sources", systemImage: "link")
                    .font(.subheadline)
                    .foregroundStyle(OneFeedTheme.graphite)
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var displayTitle: String {
        note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled draft" : note.title
    }

    private var rowText: String {
        if note.isDraft, !note.explanation.isEmpty { return note.explanation }
        if note.isDraft, !note.draftText.isEmpty { return note.draftText }
        if !note.explanation.isEmpty { return note.explanation }
        return "Ready to refine"
    }
}
#endif
