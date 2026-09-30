#if os(iOS)
import SwiftData
import SwiftUI

struct IdeaDetailView: View {
    let note: KnowledgeNote

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var isPresentingEditor = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if note.isDraft {
                    draftBadge
                    Text(note.title.isEmpty ? "Untitled draft" : note.title)
                        .font(.system(.largeTitle, design: .serif))
                        .foregroundStyle(OneFeedTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    originalCapture

                    if !note.explanation.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            GallerySectionHeader(text: "Rewrite so far")
                            RichNoteBody(text: note.explanation, formattedText: note.formattedExplanation)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    sources

                    Button {
                        isPresentingEditor = true
                    } label: {
                        Text("Refine into a note")
                    }
                    .buttonStyle(PrimaryActionStyle())

                } else {
                    Text(note.title)
                        .font(.system(.largeTitle, design: .serif))
                        .foregroundStyle(OneFeedTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 9) {
                        GallerySectionHeader(text: "Your note")
                        RichNoteBody(text: note.explanation, formattedText: note.formattedExplanation)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    sources

                    if !note.draftText.isEmpty {
                        DisclosureGroup("Original capture") {
                            Text(note.draftText)
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
                }

                NavigationLink {
                    NoteVersionsView(note: note)
                } label: {
                    Label("Version history", systemImage: "clock.arrow.circlepath")
                        .frame(minHeight: 44, alignment: .leading)
                }
                .font(.body)
                .foregroundStyle(OneFeedTheme.ink)
            }
            .padding(OneFeedTheme.pagePadding)
            .frame(maxWidth: OneFeedTheme.readingColumnWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(OneFeedTheme.paper)
        .navigationTitle(note.isDraft ? "Draft" : "Note")
        .oneFeedInlineTitle()
        .oneFeedPaperToolbar()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(note.isDraft ? "Continue draft" : "Edit note", systemImage: "pencil") {
                        isPresentingEditor = true
                    }
                    Button("Delete…", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                } label: {
                    Label("Note actions", systemImage: "ellipsis")
                }
                .accessibilityHint("Continue editing or delete this note")
            }
        }
        .sheet(isPresented: $isPresentingEditor) {
            IdeaEditorSheet(note: note)
        }
        .confirmationDialog(
            note.isDraft ? "Delete this draft?" : "Delete this note?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(note.isDraft ? "Delete draft" : "Delete note", role: .destructive, action: deleteNote)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove it from Ideas.")
        }
        .alert("Couldn’t delete", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var draftBadge: some View {
        Text("Draft")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(OneFeedTheme.graphite)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(OneFeedTheme.plaster, in: Capsule())
            .overlay { Capsule().strokeBorder(OneFeedTheme.sand, lineWidth: 1) }
            .accessibilityLabel("Draft")
    }

    private var originalCapture: some View {
        VStack(alignment: .leading, spacing: 9) {
            GallerySectionHeader(text: "Original capture")
            Text(note.draftText.isEmpty ? note.explanation : note.draftText)
                .font(.system(.body, design: .serif))
                .foregroundStyle(OneFeedTheme.ink)
                .lineSpacing(5)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var sources: some View {
        if !note.sourceTitle.isEmpty || note.sourceURL != nil || !note.sourceReferences.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                GallerySectionHeader(text: "Sources")
                if !note.sourceTitle.isEmpty {
                    IdeaSourceCitationView(note: note)
                }
                if !note.sourceReferences.isEmpty {
                    IdeaReferenceLinksView(references: note.sourceReferences)
                }
            }
        } else if note.isDraft {
            VStack(alignment: .leading, spacing: 6) {
                GallerySectionHeader(text: "Sources")
                Text("Add a web source before finishing this note.")
                    .font(.subheadline)
                    .foregroundStyle(OneFeedTheme.graphite)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func deleteNote() {
        do {
            try KnowledgeNoteStore.delete(note, in: modelContext)
            dismiss()
        } catch {
            errorMessage = "It couldn’t be deleted. It is still here. Please try again."
        }
    }
}

/// The citation uses copied note metadata so it remains readable after its
/// original article has been removed from the local library.
struct IdeaSourceCitationView: View {
    private let sourceTitle: String
    private let sourceURL: URL?
    private let author: String?
    private let publishedAt: Date?
    private let sourceKind: String?

    init(note: KnowledgeNote) {
        sourceTitle = note.sourceTitle
        sourceURL = note.sourceURL
        author = note.sourceAuthor
        publishedAt = note.sourcePublishedAt
        sourceKind = note.sourceKind
    }

    init(article: Article) {
        sourceTitle = article.title
        if article.contentKind == "youtube", let videoID = article.videoID {
            sourceURL = YouTubeProcessor.watchURL(for: videoID) ?? article.url
        } else {
            sourceURL = article.url
        }
        author = article.author
        publishedAt = article.publishedAt
        sourceKind = article.contentKind
    }

    private var safeURL: URL? {
        guard let sourceURL,
              let scheme = sourceURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = sourceURL.host,
              !host.isEmpty else { return nil }
        return sourceURL
    }

    private var displaySourceTitle: String {
        let title = sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? (safeURL?.host ?? "Open source") : title
    }

    private var metadata: String? {
        [author, publishedAt?.formatted(date: .abbreviated, time: .omitted), readableKind]
            .compactMap { value in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " · ")
            .nilIfEmpty
    }

    private var readableKind: String? {
        switch sourceKind {
        case "youtube": "Video"
        case "pdf": "PDF"
        case "epub": "Book"
        case "podcast": "Podcast"
        default: nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let safeURL {
                Link(destination: safeURL) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(displaySourceTitle)
                            .font(.body.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(OneFeedTheme.link)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .accessibilityHint("Opens the original source")
                .frame(minHeight: 44, alignment: .leading)
            } else {
                Text(displaySourceTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(OneFeedTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let metadata {
                Text(metadata)
                    .font(.subheadline)
                    .foregroundStyle(OneFeedTheme.graphite)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct IdeaReferenceLinksView: View {
    let references: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(references.enumerated()), id: \.offset) { index, reference in
                if let url = Self.validWebURL(reference) {
                    Link(destination: url) {
                        Label("Source \(index + 1) · \(url.host ?? reference)", systemImage: "link")
                            .font(.subheadline)
                            .foregroundStyle(OneFeedTheme.link)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .accessibilityHint("Opens this source in your browser")
                } else {
                    Text(reference)
                        .font(.subheadline)
                        .foregroundStyle(OneFeedTheme.graphite)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func validWebURL(_ rawValue: String) -> URL? {
        guard let components = URLComponents(string: rawValue),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty else { return nil }
        return components.url
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
#endif
