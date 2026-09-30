#if os(iOS)
import SwiftUI

/// Saved snapshots are read-only: continuing to write never replaces an earlier version.
struct NoteVersionsView: View {
    let note: KnowledgeNote

    private var versions: [KnowledgeNoteRevision] {
        note.revisions.sorted {
            if $0.savedAt != $1.savedAt { return $0.savedAt > $1.savedAt }
            return $0.id.uuidString > $1.id.uuidString
        }
    }

    var body: some View {
        List {
            if versions.isEmpty {
                Text("Earlier versions will appear here when you save your next changes.")
                    .foregroundStyle(OneFeedTheme.graphite)
                    .listRowBackground(OneFeedTheme.paper)
            }
            ForEach(versions) { version in
                NavigationLink {
                    NoteRevisionView(version: version)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(version.isDraft ? "Saved draft" : "Finished note", systemImage: version.isDraft ? "pencil" : "checkmark.circle")
                            .font(.headline)
                            .foregroundStyle(OneFeedTheme.ink)
                        Text(version.title)
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(OneFeedTheme.ink)
                        Text(version.savedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(OneFeedTheme.graphite)
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(OneFeedTheme.paper)
            }
        }
        .oneFeedGroupedListStyle()
        .navigationTitle("Version history")
        .oneFeedInlineTitle()
        .oneFeedPaperToolbar()
    }
}

private struct NoteRevisionView: View {
    let version: KnowledgeNoteRevision

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(version.isDraft ? "Saved draft" : "Finished note")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(OneFeedTheme.graphite)
                    Text(version.title)
                        .font(.system(.largeTitle, design: .serif))
                        .foregroundStyle(OneFeedTheme.ink)
                    Text(version.savedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(OneFeedTheme.graphite)
                }
                if !version.explanation.isEmpty {
                    RichNoteBody(text: version.explanation, formattedText: version.formattedExplanation)
                }
                if !version.draftText.isEmpty {
                    if version.isDraft && version.explanation.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            GallerySectionHeader(text: "Rough draft")
                            Text(version.draftText)
                                .font(.system(.body, design: .serif))
                                .foregroundStyle(OneFeedTheme.ink)
                                .textSelection(.enabled)
                        }
                    } else {
                        DisclosureGroup("Original capture") {
                        Text(version.draftText)
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(OneFeedTheme.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    GallerySectionHeader(text: "Sources in this version")
                    if !version.sourceTitle.isEmpty {
                        if let raw = version.sourceURL, let url = webURL(raw) {
                            Link(version.sourceTitle, destination: url)
                                .foregroundStyle(OneFeedTheme.link)
                        } else {
                            Text(version.sourceTitle).foregroundStyle(OneFeedTheme.ink)
                        }
                        if let author = version.sourceAuthor, !author.isEmpty {
                            Text(author).font(.subheadline).foregroundStyle(OneFeedTheme.graphite)
                        }
                        if let date = version.sourcePublishedAt {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .font(.subheadline).foregroundStyle(OneFeedTheme.graphite)
                        }
                    }
                    ForEach(Array(version.sourceReferences.enumerated()), id: \.offset) { _, reference in
                        if let url = webURL(reference) {
                            Link(reference, destination: url)
                                .foregroundStyle(OneFeedTheme.link)
                        } else {
                            Text(reference).foregroundStyle(OneFeedTheme.graphite)
                        }
                    }
                    if version.sourceTitle.isEmpty && version.sourceReferences.isEmpty {
                        Text("No sources attached yet.")
                            .foregroundStyle(OneFeedTheme.graphite)
                    }
                }
                .font(.body)
            }
            .padding(OneFeedTheme.pagePadding)
            .frame(maxWidth: OneFeedTheme.readingColumnWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(OneFeedTheme.paper)
        .navigationTitle("Saved version")
        .oneFeedInlineTitle()
        .oneFeedPaperToolbar()
    }

    private func webURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
#endif
