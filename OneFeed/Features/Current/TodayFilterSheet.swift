import SwiftData
import SwiftUI

/// Chooses which folders and sources are allowed to fill Today.
struct TodayFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    #if os(iOS)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #endif
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @State private var appliedSearch = ""
    @State private var presentedError: String?
    @State private var folderCache = TodayFolderCache()

    var onUpdated: () -> Void

    var body: some View {
        NavigationStack {
            OneFeedSearchHost("Folders or sources", applied: $appliedSearch) {
                filterList
            }
            .tint(OneFeedTheme.ink)
            .navigationTitle("In Today")
            .oneFeedInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Couldn’t update Today", isPresented: Binding(
                get: { presentedError != nil },
                set: { if !$0 { presentedError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(presentedError ?? "")
            }
        }
        .oneFeedMacFormSheet()
        #if os(iOS)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private var filterList: some View {
        Group {
            if feeds.isEmpty {
                EmptyLibraryState(
                    title: "No sources yet",
                    systemImage: "dot.radiowaves.left.and.right",
                    description: "Add a source in Feed, then choose whether it fills Today."
                )
            } else if visibleFolders.isEmpty {
                EmptyLibraryState(
                    title: "No matches",
                    systemImage: "magnifyingglass",
                    description: "Try a folder or source name."
                )
            } else {
                filterRows
            }
        }
        .background(OneFeedTheme.plaster)
    }

    private var filterRows: some View {
        List {
                    ForEach(Array(visibleFolders.enumerated()), id: \.element.id) { index, folder in
                        Section {
                            if folder.offersAllSources {
                                allSourcesToggle(folder.group)
                            }
                            ForEach(folder.shown) { feed in
                                sourceToggle(feed)
                            }
                        } header: {
                            GallerySectionHeader(text: "\(FolderEmoji.glyph(for: folder.group.name)) \(folder.group.name)")
                        } footer: {
                            if index == visibleFolders.count - 1 {
                                Text("Today is a short stack from the sources you leave on. Everything else stays in Feed. A source in two folders uses one switch.")
                            }
                        }
                        .listRowBackground(OneFeedTheme.paper)
                    }
        }
        .oneFeedGroupedListStyle()
    }

    private func allSourcesToggle(_ group: FeedFolderGroup) -> some View {
        let included = group.feeds.filter(\.includeInToday).count
        let mixed = included > 0 && included < group.feeds.count
        return Toggle(isOn: folderBinding(group)) {
            VStack(alignment: .leading, spacing: 2) {
                Text("All sources")
                    .foregroundStyle(OneFeedTheme.ink)
                if mixed {
                    Text("Some are in Today")
                        .font(.caption)
                        .foregroundStyle(OneFeedTheme.graphite)
                }
            }
        }
        .accessibilityLabel("All sources in \(group.name)")
        .accessibilityValue(mixed ? "Some sources" : (included == group.feeds.count ? "On" : "Off"))
    }

    private func sourceToggle(_ feed: Feed) -> some View {
        Toggle(isOn: inclusionBinding(for: feed)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(feed.title)
                    .foregroundStyle(OneFeedTheme.ink)
                    .multilineTextAlignment(.leading)
                if !feed.isEnabled {
                    Text("Paused")
                        .font(.caption)
                        .foregroundStyle(OneFeedTheme.graphite)
                }
            }
        }
        .accessibilityHint(feed.isEnabled ? "Includes this source in Today" : "Paused sources stay out of Today until you resume them")
    }

    private func folderBinding(_ group: FeedFolderGroup) -> Binding<Bool> {
        Binding(
            get: { group.feeds.allSatisfy(\.includeInToday) },
            set: { apply($0, to: group.feeds) }
        )
    }

    private func inclusionBinding(for feed: Feed) -> Binding<Bool> {
        Binding(
            get: { feed.includeInToday },
            set: { apply($0, to: [feed]) }
        )
    }

    private func apply(_ included: Bool, to feeds: [Feed]) {
        do {
            try DailyDeckService.setIncludedInToday(included, feeds: feeds, in: modelContext)
            onUpdated()
        } catch {
            presentedError = RefreshFailure.message(for: error, fallback: "Try again.")
        }
    }

    private var visibleFolders: [TodayFolderFilter] {
        let groups = folderCache.groups(from: feeds)
        let query = appliedSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return groups.map {
                TodayFolderFilter(group: $0, shown: $0.feeds, offersAllSources: $0.feeds.count > 1)
            }
        }
        return groups.compactMap { group in
            let folderMatches = group.name.localizedStandardContains(query)
            let shown = folderMatches
                ? group.feeds
                : group.feeds.filter { $0.title.localizedStandardContains(query) }
            guard folderMatches || !shown.isEmpty else { return nil }
            return TodayFolderFilter(
                group: group,
                shown: shown,
                offersAllSources: folderMatches && group.feeds.count > 1
            )
        }
    }
}

/// Folder rows stay grouped until a source is added, renamed, or moved.
/// Turning a source on or off for Today does not rebuild them.
final class TodayFolderCache {
    private var edge = Int.min
    private var cached: [FeedFolderGroup] = []
    private(set) var loads = 0

    func groups(from feeds: [Feed]) -> [FeedFolderGroup] {
        let next = Self.edge(of: feeds)
        if next == edge { return cached }
        loads += 1
        cached = FeedFolderGrouping.groups(from: feeds)
        edge = next
        return cached
    }

    private static func edge(of feeds: [Feed]) -> Int {
        var token = ListIdentity.token(ids: feeds.lazy.map(\.id))
        for feed in feeds {
            token = token &* 31 &+ feed.title.hashValue
            token = token &* 31 &+ feed.memberships.hashValue
        }
        return token
    }
}

private struct TodayFolderFilter: Identifiable {
    let group: FeedFolderGroup
    let shown: [Feed]
    let offersAllSources: Bool
    var id: FeedFolderID { group.folderID }
}
