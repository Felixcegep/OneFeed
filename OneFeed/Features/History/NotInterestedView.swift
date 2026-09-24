import SwiftData
import SwiftUI

struct NotInterestedView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \NotInterestedEntry.recordedAt, order: .reverse) private var entries: [NotInterestedEntry]
    @Query private var feeds: [Feed]
    @State private var selectedArticle: Article?
    @State private var pendingRemoval: NotInterestedSourceGroup?
    @State private var librarianPrompt: LibrarianPrompt?
    @State private var listCache = NotInterestedListCache()
    /// Source groups stay put while a row redraws. Rebuilt off the main thread when a mark is added, removed, or recorded again.
    @State private var grouped: [NotInterestedSourceGroup] = []
    @State private var logReady = false
    @State private var isRemovingSource = false
    @State private var queueError: String?
    @State private var storyError: String?
    @State private var removeError: String?
    @State private var sourceError: String?
    @State private var logError: String?

    /// Changes when a mark is added, removed, or recorded again. A title edit shows on the row without regrouping.
    private var logStamp: Int {
        var stamp = entries.count
        for entry in entries {
            stamp ^= entry.persistentModelID.hashValue
            stamp ^= entry.recordedAt.hashValue
        }
        return stamp
    }

    private func reloadLog() async {
        let edge = logStamp
        let snaps = entries.map(NotInterestedEntrySnap.init)
        let guids = entries.map(\.articleGUID)
        let plans = await Task.detached(priority: .userInitiated) {
            NotInterestedListPlan.groups(from: snaps)
        }.value
        guard !Task.isCancelled, edge == logStamp else { return }
        let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let groups = plans.map { plan in
            NotInterestedSourceGroup(
                sourceTitle: plan.sourceTitle,
                sourceFeedURL: plan.sourceFeedURL,
                sourceWebsiteURL: plan.sourceWebsiteURL,
                feedID: plan.feedID,
                entries: plan.entryIDs.compactMap { byID[$0] }
            )
        }
        listCache.resolve(entries: entries, guids: guids, in: modelContext)
        grouped = groups
        logReady = true
    }

    var body: some View {
        Group {
            if !logReady && grouped.isEmpty {
                Color.clear
                    .frame(height: 1)
                    .accessibilityHidden(true)
            } else if grouped.isEmpty {
                EmptyLibraryState(
                    title: "Nothing set aside",
                    systemImage: "hand.thumbsdown",
                    description: "Skip a story, then choose Not interested. Those articles stay here, grouped by source."
                )
            } else {
                List {
                    ForEach(grouped) { group in
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
        .oneFeedScrollEdge()
        .background(OneFeedTheme.plaster)
        .task(id: logStamp) {
            await reloadLog()
        }
        .toolbar {
            if !grouped.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Ask Gemini") {
                        librarianPrompt = LibrarianPrompt(preparesReview: true)
                    }
                }
            }
        }
        .navigationDestination(item: $librarianPrompt) { prompt in
            ExperimentalLibrarianView(
                initialPrompt: prompt.preparesReview ? nil : prompt.text,
                preparesReviewPrompt: prompt.preparesReview
            )
        }
        .oneFeedArticleCover(item: $selectedArticle) { article in
            ReaderView(article: article, onFinish: { state in
                guard article.isStored else {
                    selectedArticle = nil
                    return true
                }
                if state == .saved {
                    do {
                        try ArticleQueueService().moveToQueue(article, in: modelContext)
                    } catch {
                        queueError = UserFacingFailure.message(for: error, fallback: "Couldn’t put that in Queue.")
                        return false
                    }
                } else {
                    do {
                        try ArticleActions.apply(state, to: article, in: modelContext)
                    } catch {
                        storyError = UserFacingFailure.message(for: error, fallback: "Couldn’t update that story.")
                        return false
                    }
                }
                selectedArticle = nil
                return true
            }, onClose: {
                selectedArticle = nil
            })
            .onAppear { LibrarySyncService.shared.hasActiveReadingSession = true }
            .onDisappear { LibrarySyncService.shared.hasActiveReadingSession = false }
        }
        .alert("Couldn’t put that in Queue", isPresented: Binding(
            get: { queueError != nil },
            set: { if !$0 { queueError = nil } }
        )) {
            Button("OK", role: .cancel) { queueError = nil }
        } message: {
            Text(queueError ?? "")
        }
        .alert("Couldn’t update that story", isPresented: Binding(
            get: { storyError != nil },
            set: { if !$0 { storyError = nil } }
        )) {
            Button("OK", role: .cancel) { storyError = nil }
        } message: {
            Text(storyError ?? "")
        }
        .alert("Couldn’t remove that source", isPresented: Binding(
            get: { removeError != nil },
            set: { if !$0 { removeError = nil } }
        )) {
            Button("OK", role: .cancel) { removeError = nil }
        } message: {
            Text(removeError ?? "")
        }
        .alert("Couldn’t update that source", isPresented: Binding(
            get: { sourceError != nil },
            set: { if !$0 { sourceError = nil } }
        )) {
            Button("OK", role: .cancel) { sourceError = nil }
        } message: {
            Text(sourceError ?? "")
        }
        .alert("Couldn’t remove that entry", isPresented: Binding(
            get: { logError != nil },
            set: { if !$0 { logError = nil } }
        )) {
            Button("OK", role: .cancel) { logError = nil }
        } message: {
            Text(logError ?? "")
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
                guard let group = pendingRemoval else { return }
                pendingRemoval = nil
                Task { await removeSource(group) }
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
                        do {
                            try NotInterestedLog.archive(feed, in: modelContext)
                        } catch {
                            sourceError = UserFacingFailure.message(for: error, fallback: "Couldn’t update that source.")
                        }
                    }
                    if feed.includeInToday {
                        Button("Take out of Today", systemImage: "sun.min") {
                            do {
                                try NotInterestedLog.takeOutOfToday(feed, in: modelContext)
                            } catch {
                                sourceError = UserFacingFailure.message(for: error, fallback: "Couldn’t update that source.")
                            }
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
        let article = listCache.article(for: entry, in: modelContext)
        return Button {
            selectedArticle = article
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.articleTitle)
                    .font(.headline)
                    .foregroundStyle(OneFeedTheme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(OneFeedDateLabel.historySection(entry.recordedAt))
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
                removeLogEntry(entry)
            }
        }
        .contextMenu {
            Button("Remove from log", systemImage: "trash", role: .destructive) {
                removeLogEntry(entry)
            }
        }
        .accessibilityHint(article == nil ? "The article is no longer on this device" : "Opens this article")
    }

    private func removeLogEntry(_ entry: NotInterestedEntry) {
        do {
            try NotInterestedLog.delete(entry, in: modelContext)
        } catch {
            logError = UserFacingFailure.message(for: error, fallback: "Couldn’t remove that entry.")
        }
    }

    private func sourceDetail(for group: NotInterestedSourceGroup, feed: Feed?) -> String {
        let count = group.count == 1 ? "1 article" : "\(group.count) articles"
        guard let feed else { return "\(count) · source removed" }
        if feed.memberships.count == 1, feed.containsFolder(NotInterestedLog.archiveFolderName) {
            return "\(count) · Archive"
        }
        var parts = [count]
        if !feed.memberships.isEmpty {
            parts.append(feed.memberships.joined(separator: ", "))
        }
        if !feed.includeInToday {
            parts.append("not in Today")
        }
        return parts.joined(separator: " · ")
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
        guard !isRemovingSource else { return }
        guard let feed = NotInterestedLog.feed(matching: group, in: feeds) else { return }
        isRemovingSource = true
        defer { isRemovingSource = false }
        do {
            try await FreshRSSSyncService().removeSubscription(feed, in: modelContext)
        } catch {
            modelContext.delete(feed)
            do {
                try modelContext.save()
                LibraryChange.noteRemovedFeed(feed)
            } catch {
                modelContext.rollback()
                removeError = UserFacingFailure.message(for: error, fallback: "Couldn’t remove that source.")
            }
        }
    }
}

private final class NotInterestedListCache {
    private var articles: [PersistentIdentifier: Article?] = [:]

    /// One story lookup for the visible log. Bodies stay on disk until a row opens.
    func resolve(entries: [NotInterestedEntry], guids: [String], in context: ModelContext) {
        articles.removeAll()
        let matches = NotInterestedLog.articles(matchingGUIDs: guids, in: context)
        for entry in entries {
            if let match = matches[entry.articleGUID] {
                articles[entry.persistentModelID] = match
            }
        }
    }

    func article(for entry: NotInterestedEntry, in context: ModelContext) -> Article? {
        if let cached = articles[entry.persistentModelID] { return cached }
        let found = NotInterestedLog.article(for: entry, in: context)
        articles[entry.persistentModelID] = found
        return found
    }
}

private struct LibrarianPrompt: Identifiable, Hashable {
    let id = UUID()
    var text = ""
    var preparesReview = false
}
