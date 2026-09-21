import SwiftData
import SwiftUI

struct NotInterestedView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \NotInterestedEntry.recordedAt, order: .reverse) private var entries: [NotInterestedEntry]
    @Query private var feeds: [Feed]
    @State private var selectedArticle: Article?
    @State private var pendingRemoval: NotInterestedSourceGroup?
    @State private var librarianPrompt: LibrarianPrompt?

    private var groups: [NotInterestedSourceGroup] {
        NotInterestedLog.groups(from: entries)
    }

    var body: some View {
        Group {
            if groups.isEmpty {
                EmptyLibraryState(
                    title: "Nothing set aside",
                    systemImage: "hand.thumbsdown",
                    description: "Articles you mark not interested stay here, grouped by source."
                )
            } else {
                List {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.entries) { entry in
                                entryRow(entry)
                            }
                        } header: {
                            sourceHeader(group)
                        }
                    }
                }
                .oneFeedGroupedListStyle()
            }
        }
        .navigationTitle("Not interested")
        .oneFeedInlineTitle()
        .oneFeedPaperToolbar()
        .background(OneFeedTheme.plaster)
        .toolbar {
            if !groups.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Ask Gemini") {
                        librarianPrompt = LibrarianPrompt(text: NotInterestedLog.reviewPrompt(in: modelContext))
                    }
                }
            }
        }
        .navigationDestination(item: $librarianPrompt) { prompt in
            ExperimentalLibrarianView(initialPrompt: prompt.text)
        }
        .oneFeedArticleCover(item: $selectedArticle) { article in
            ReaderView(article: article) { _ in selectedArticle = nil }
        }
        .confirmationDialog(
            "Remove \(pendingRemoval?.sourceTitle ?? "this source") and its locally stored articles?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove source", role: .destructive) {
                if let group = pendingRemoval {
                    Task { await removeSource(group) }
                }
                pendingRemoval = nil
            }
        }
    }

    private func sourceHeader(_ group: NotInterestedSourceGroup) -> some View {
        let feed = NotInterestedLog.feed(matching: group, in: feeds)
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.sourceTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OneFeedTheme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(sourceDetail(for: group, feed: feed))
                    .font(.caption)
                    .foregroundStyle(OneFeedTheme.graphite)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, 4)
            .padding(.bottom, 8)

            if let feed {
                Menu {
                    Button("Move to Archive", systemImage: "archivebox") {
                        NotInterestedLog.archive(feed, in: modelContext)
                    }
                    if feed.includeInToday {
                        Button("Take out of Today", systemImage: "sun.min") {
                            NotInterestedLog.takeOutOfToday(feed, in: modelContext)
                        }
                    }
                    Button("Ask Gemini about this source", systemImage: "text.bubble") {
                        librarianPrompt = LibrarianPrompt(text: sourcePrompt(for: group))
                    }
                    Button("Remove source", systemImage: "trash", role: .destructive) {
                        pendingRemoval = group
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(OneFeedTheme.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Actions for \(group.sourceTitle)")
            }
        }
        .textCase(nil)
    }

    private func entryRow(_ entry: NotInterestedEntry) -> some View {
        let article = NotInterestedLog.article(for: entry, in: modelContext)
        return Button {
            selectedArticle = article
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.articleTitle)
                    .font(.headline)
                    .foregroundStyle(OneFeedTheme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.recordedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(OneFeedTheme.graphite)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .buttonStyle(DirectoryRowButtonStyle())
        .articleListRow()
        .disabled(article == nil)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Remove", systemImage: "trash", role: .destructive) {
                NotInterestedLog.delete(entry, in: modelContext)
            }
        }
        .contextMenu {
            Button("Remove from log", systemImage: "trash", role: .destructive) {
                NotInterestedLog.delete(entry, in: modelContext)
            }
        }
        .accessibilityHint(article == nil ? "The article is no longer on this device" : "Opens this article")
    }

    private func sourceDetail(for group: NotInterestedSourceGroup, feed: Feed?) -> String {
        let count = group.count == 1 ? "1 article" : "\(group.count) articles"
        guard let feed else { return "\(count) · source removed" }
        if feed.folderName?.caseInsensitiveCompare(NotInterestedLog.archiveFolderName) == .orderedSame {
            return "\(count) · Archive"
        }
        if !feed.includeInToday {
            return "\(count) · not in Today"
        }
        if let folder = feed.folderName?.trimmingCharacters(in: .whitespacesAndNewlines), !folder.isEmpty {
            return "\(count) · \(folder)"
        }
        return count
    }

    private func sourcePrompt(for group: NotInterestedSourceGroup) -> String {
        let titles = group.entries.prefix(8).map { "· \($0.articleTitle)" }.joined(separator: "\n")
        let extra = group.count > 8 ? "\n· …and \(group.count - 8) more" : ""
        return """
        I marked these articles as not interested from \(group.sourceTitle). Consider moving it to Archive, adding blocked words, or removing it if I ask.

        \(titles)\(extra)
        """
    }

    private func removeSource(_ group: NotInterestedSourceGroup) async {
        guard let feed = NotInterestedLog.feed(matching: group, in: feeds) else { return }
        do {
            try await FreshRSSSyncService().removeSubscription(feed, in: modelContext)
        } catch {
            LibraryChange.noteRemovedFeed(feed)
            modelContext.delete(feed)
            try? modelContext.save()
        }
    }
}

private struct LibrarianPrompt: Identifiable, Hashable {
    let text: String
    var id: String { text }
}
