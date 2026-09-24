import SwiftData
import SwiftUI

struct SourcesView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SourcesViewModel()
    @State private var addPreferredFolder: String?
    @State private var pickingFolder: FolderIconTarget?
    @State private var iconTick = 0
    @State private var appliedSearch = ""
    @State private var folderToRemove: String?

    private var folderQuery: String {
        appliedSearch.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleFolders: [FeedFolderGroup] {
        let query = folderQuery
        guard !query.isEmpty else { return viewModel.folders }
        return viewModel.folders.filter { folder in
            folder.name.localizedStandardContains(query)
                || folder.feeds.contains { $0.title.localizedStandardContains(query) }
        }
    }

    var body: some View {
        let _ = iconTick
        OneFeedSearchHost("Folders or sources", applied: $appliedSearch) {
            sourcesList
        }
        .navigationTitle("Sources")
        .oneFeedLargeTitle()
        .oneFeedScrollEdge()
        .task { viewModel.configure(with: modelContext) }
        .toolbar {
            ToolbarItem(placement: .oneFeedTrailing) {
                Menu {
                    Button("Add Source", systemImage: "dot.radiowaves.left.and.right") { presentAdd() }
                    Button("New Folder", systemImage: "folder.badge.plus") {
                        viewModel.newFolderName = ""
                        viewModel.isPresentingNewFolder = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add source or folder")
            }
            ToolbarItem(placement: .oneFeedTrailing) {
                Menu {
                    Button("Restore all seeded sources", systemImage: "arrow.triangle.2.circlepath") {
                        viewModel.importAllSeededSources()
                    }
                    .disabled(viewModel.isImportingPack)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
            }
        }
        .sheet(isPresented: $viewModel.isPresentingAddSource, onDismiss: {
            addPreferredFolder = nil
        }) {
            AddSourceView(preferredFolder: addPreferredFolder, onAdded: { viewModel.reload() })
        }
        .sheet(item: $pickingFolder) { target in
            FolderEmojiPicker(folderName: target.name) { _ in
                iconTick += 1
            }
        }
        .alert("New Folder", isPresented: $viewModel.isPresentingNewFolder) {
            TextField("Must read, Builders…", text: $viewModel.newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { viewModel.createFolder() }
        } message: {
            Text("Folders group sources. Add feeds into it next.")
        }
        .alert(viewModel.statusTitle ?? "Sources", isPresented: Binding(
            get: { viewModel.statusTitle != nil },
            set: { if !$0 { viewModel.clearStatus() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.statusMessage ?? "")
        }
        .confirmationDialog(
            "Remove empty folder?",
            isPresented: Binding(
                get: { folderToRemove != nil },
                set: { if !$0 { folderToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let folderToRemove {
                Button("Remove \(folderToRemove)", role: .destructive) {
                    FolderStore.remove(folderToRemove)
                    LibraryChange.noteStructureChanged()
                    viewModel.reload()
                    self.folderToRemove = nil
                }
            }
        } message: {
            Text("This folder has no sources.")
        }
    }

    private var sourcesList: some View {
        Group {
            if visibleFolders.isEmpty {
                if folderQuery.isEmpty {
                    EmptyLibraryState(
                        title: "No folders yet",
                        systemImage: "folder",
                        description: "Add a source or create a folder to organize your reading.",
                        actionTitle: "Add Source",
                        action: { presentAdd() }
                    )
                } else {
                    EmptyLibraryState(
                        title: "No matches",
                        systemImage: "magnifyingglass",
                        description: "Try a folder or source name."
                    )
                }
            } else {
                sourcesFolderList
            }
        }
    }

    private var sourcesFolderList: some View {
        List {
                if visibleFolders.contains(where: { !$0.feeds.isEmpty }) {
                    Section {
                        ForEach(visibleFolders.filter { !$0.feeds.isEmpty }) { folder in
                            folderLink(folder)
                        }
                    } header: {
                        GallerySectionHeader(text: "With sources")
                    }
                }
                if visibleFolders.contains(where: { $0.feeds.isEmpty }) {
                    Section {
                        ForEach(visibleFolders.filter { $0.feeds.isEmpty }) { folder in
                            folderLink(folder)
                        }
                    } header: {
                        GallerySectionHeader(text: "Empty folders")
                    }
                }
        }
        .oneFeedGroupedListStyle()
    }

    private func folderLink(_ folder: FeedFolderGroup) -> some View {
        HStack(spacing: 4) {
            FolderEmojiButton(name: folder.name) {
                pickingFolder = FolderIconTarget(name: folder.name)
            }
            NavigationLink {
                FolderFeedsView(
                    folderID: folder.folderID,
                    viewModel: viewModel,
                    onAddInFolder: {
                        addPreferredFolder = folder.folderID == .unfiled ? nil : folder.name
                        viewModel.isPresentingAddSource = true
                    }
                )
            } label: {
                FolderRow(folder: folder)
            }
        }
        .accessibilityIdentifier("folder-\(folder.name)")
        .sourceManageRow()
        .contextMenu {
            Button("Change icon", systemImage: "face.smiling") {
                pickingFolder = FolderIconTarget(name: folder.name)
            }
            if folder.feeds.isEmpty, case .named = folder.folderID {
                Button("Remove empty folder", systemImage: "trash", role: .destructive) {
                    folderToRemove = folder.name
                }
            }
        }
    }

    private func presentAdd(folder: String? = nil) {
        addPreferredFolder = folder
        viewModel.isPresentingAddSource = true
    }
}

private struct FolderRow: View {
    let folder: FeedFolderGroup
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.body)
                    .foregroundStyle(OneFeedTheme.ink)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                if let preview {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(OneFeedTheme.graphite)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !folder.feeds.isEmpty {
                Text("\(folder.feeds.count)")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(OneFeedTheme.graphite)
                    .accessibilityLabel(sourceCount)
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens feeds in this folder")
    }

    private var preview: String? {
        let titles = folder.feeds.prefix(3).map(\.title)
        guard !titles.isEmpty else { return nil }
        return titles.joined(separator: ", ")
    }

    private var sourceCount: String {
        switch folder.feeds.count {
        case 1: "1 source"
        default: "\(folder.feeds.count) sources"
        }
    }
}

private struct FolderFeedsView: View {
    let folderID: FeedFolderID
    let viewModel: SourcesViewModel
    var onAddInFolder: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var appliedSearch = ""

    private var otherFolders: [String] {
        viewModel.folderNames.filter { name in
            guard case .named(let current) = folderID else { return true }
            return name.caseInsensitiveCompare(current) != .orderedSame
        }
    }

    private var visibleFeeds: [Feed] {
        let feeds = viewModel.feeds(in: folderID)
        let query = appliedSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return feeds }
        return feeds.filter {
            $0.title.localizedStandardContains(query)
                || $0.feedURL.absoluteString.localizedStandardContains(query)
        }
    }

    var body: some View {
        OneFeedSearchHost("Sources in this folder", applied: $appliedSearch) {
            folderFeedList
        }
    }

    private var folderFeedList: some View {
        Group {
            if visibleFeeds.isEmpty {
                if appliedSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    EmptyLibraryState(
                        title: "No sources yet",
                        systemImage: "dot.radiowaves.left.and.right",
                        description: "Add a source to start filling this folder.",
                        actionTitle: "Add Source",
                        action: onAddInFolder
                    )
                } else {
                    EmptyLibraryState(
                        title: "No matches",
                        systemImage: "magnifyingglass",
                        description: "Try a source name."
                    )
                }
            } else {
                folderFeedRows
            }
        }
        .navigationTitle(folderID.title)
        .oneFeedLargeTitle()
        .oneFeedScrollEdge()
        .background(OneFeedTheme.plaster)
        .toolbar {
            ToolbarItem(placement: .oneFeedTrailing) {
                Button("Add Source", systemImage: "plus") { onAddInFolder() }
            }
        }
    }

    private var folderFeedRows: some View {
        List {
            Section {
                ForEach(visibleFeeds) { feed in
                    NavigationLink {
                        SourceDetailView(feed: feed, context: modelContext)
                    } label: {
                        SourceRow(feed: feed, folderID: folderID)
                    }
                    .sourceManageRow()
                    .contextMenu {
                        Menu("Also in…") {
                            ForEach(otherFolders, id: \.self) { name in
                                Button {
                                    viewModel.toggle(feed, folder: name)
                                } label: {
                                    if feed.containsFolder(name) {
                                        Label(name, systemImage: "checkmark")
                                    } else {
                                        Text(name)
                                    }
                                }
                            }
                        }
                        if case .named(let current) = folderID {
                            Button("Remove from \(current)") {
                                viewModel.remove(feed, from: current)
                            }
                        }
                    }
                }
            }
        }
        .oneFeedGroupedListStyle()
    }
}

private struct SourceRow: View {
    let feed: Feed
    var folderID: FeedFolderID? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(OneFeedTheme.graphite)
                .frame(width: 36, height: 36)
                .background(OneFeedTheme.warm1, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(feed.title)
                    .font(.body)
                    .foregroundStyle(OneFeedTheme.ink)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                if let alsoIn {
                    Text(alsoIn)
                        .font(.subheadline)
                        .foregroundStyle(OneFeedTheme.graphite)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(OneFeedTheme.graphite)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityHint(feed.isEnabled ? "Opens source details" : "Paused. Opens source details")
    }

    private var alsoIn: String? {
        guard case .named(let name) = folderID else { return nil }
        return feed.alsoInLine(excluding: name)
    }

    private var symbol: String {
        switch feed.contentKind {
        case "pdf": "doc.text"
        case "epub": "book.closed"
        case "page": "doc.plaintext"
        default: "dot.radiowaves.left.and.right"
        }
    }

    private var subtitle: String {
        let host = feed.websiteURL?.host() ?? feed.feedURL.host() ?? feed.feedURL.absoluteString
        let kind = kindLabel
        if !feed.isEnabled { return kind.map { "\(host) · \($0) · Paused" } ?? "\(host) · Paused" }
        if feed.remoteID != nil { return "\(host) · Synced" }
        return kind.map { "\(host) · \($0)" } ?? host
    }

    private var kindLabel: String? {
        switch feed.contentKind {
        case "pdf": "PDF"
        case "epub": "EPUB"
        case "page": "Article"
        default: nil
        }
    }

}

private extension View {
    func sourceManageRow() -> some View {
        listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowSeparator(.visible, edges: .bottom)
            .listRowSeparatorTint(OneFeedTheme.sand)
            .listRowBackground(OneFeedTheme.paper)
    }
}

private struct SourceDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: SourceDetailViewModel
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var selectedArticle: Article?

    init(feed: Feed, context: ModelContext) {
        _viewModel = State(initialValue: SourceDetailViewModel(feed: feed, context: context))
    }

    var body: some View {
        Form {
            Section {
                StackedLabeledValue(title: "Website", value: viewModel.feed.websiteURL?.host() ?? "—")
                StackedLabeledValue(title: addressTitle, value: viewModel.feed.feedURL.absoluteString)
            }
            .listRowBackground(OneFeedTheme.paper)
            Section {
                if viewModel.availableFolders.isEmpty {
                    Text("No folders yet")
                        .foregroundStyle(OneFeedTheme.graphite)
                }
                ForEach(viewModel.availableFolders, id: \.self) { name in
                    Button {
                        viewModel.toggleFolder(name)
                    } label: {
                        HStack {
                            Text(name)
                                .foregroundStyle(OneFeedTheme.ink)
                            Spacer()
                            if viewModel.feed.containsFolder(name) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(OneFeedTheme.ink)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                Button("New Folder…") { isCreatingFolder = true }
            } header: {
                GallerySectionHeader(text: "Folders")
            } footer: {
                    Text("This source can live in more than one folder. Uncheck a folder to take it out of that list.")
            }
            .listRowBackground(OneFeedTheme.paper)
            Section {
                Toggle("Included in Feed", isOn: $viewModel.isEnabled)
                Toggle("Included in Today", isOn: $viewModel.includeInToday)
                if viewModel.feed.refreshesOverRSS {
                    Toggle("Include videos", isOn: $viewModel.includeVideos)
                    Toggle("Include Shorts", isOn: $viewModel.includeShorts)
                }
            } footer: {
                Text(viewModel.feed.refreshesOverRSS
                    ? "Today is a small daily stack. Videos shorter than 3 minutes are skipped unless you allow Shorts."
                    : "This source is one article or file. It opens in the reader on this device.")
            }
            .listRowBackground(OneFeedTheme.paper)
            if viewModel.feed.refreshesOverRSS {
                Section {
                    TextField("AI, Sponsored…", text: $viewModel.blockedWords, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    GallerySectionHeader(text: "Blocked words")
                } footer: {
                    Text("Comma or new-line separated. Matching items never enter Today or Feed.")
                }
                .listRowBackground(OneFeedTheme.paper)
            }
            if !viewModel.recentArticles.isEmpty {
                Section {
                    ForEach(viewModel.recentArticles) { article in
                        Button {
                            selectedArticle = article
                        } label: {
                            ArticleRow(article: article)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    GallerySectionHeader(text: viewModel.feed.refreshesOverRSS ? "Recent" : "Read")
                }
                .listRowBackground(OneFeedTheme.paper)
            }
            Section {
                Button("Remove Source", role: .destructive) { viewModel.isConfirmingRemoval = true }
            }
            .listRowBackground(OneFeedTheme.paper)
        }
        .navigationTitle(viewModel.feed.title)
        .oneFeedInlineTitle()
        .oneFeedPaperScreen()
        .oneFeedScrollEdge()
        .refreshProgressBanner(viewModel.progress)
        .toolbar {
            if viewModel.feed.refreshesOverRSS {
                ToolbarItem(placement: .oneFeedTrailing) {
                    OneFeedToolbarRefresh(isRefreshing: viewModel.isRefreshing) {
                        Task { await viewModel.refresh() }
                    }
                }
            }
        }
        .alert("Couldn’t refresh", isPresented: Binding(
            get: { viewModel.refreshError != nil },
            set: { if !$0 { viewModel.refreshError = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.refreshError = nil }
        } message: {
            Text(viewModel.refreshError ?? "")
        }
        .oneFeedArticleCover(item: $selectedArticle) { article in
            ReaderView(article: article) { state in
                selectedArticle = nil
                guard article.isStored else { return }
                ArticleActions.apply(state, to: article, in: modelContext)
            }
            .onAppear { LibrarySyncService.shared.hasActiveReadingSession = true }
            .onDisappear { LibrarySyncService.shared.hasActiveReadingSession = false }
        }
        .alert("New Folder", isPresented: $isCreatingFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) { newFolderName = "" }
            Button("Add Here") {
                let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                FolderStore.remember(name)
                viewModel.reloadFolders()
                viewModel.addFolder(name)
                newFolderName = ""
            }
        }
        .confirmationDialog("Remove this source and its locally stored articles?", isPresented: $viewModel.isConfirmingRemoval, titleVisibility: .visible) {
            Button("Remove Source", role: .destructive) {
                dismiss()
                Task { @MainActor in await viewModel.remove() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { viewModel.commitBlockedWords() }
        }
        .onDisappear { viewModel.commitBlockedWords() }
    }

    private var addressTitle: String {
        switch viewModel.feed.contentKind {
        case "pdf": "PDF"
        case "epub": "EPUB"
        case "page": "Article"
        default: "Feed"
        }
    }
}

struct AddSourceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @State private var viewModel = AddSourceViewModel()
    @State private var showSuccess = false

    var preferredFolder: String? = nil
    /// Prefills the address field (e.g. from a `feed:` / Share / deep link).
    var initialAddress: String? = nil
    /// Runs after at least one source is saved. Cancel does not call this.
    var onAdded: () -> Void = {}

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("example.com/feed\nexample.com/paper.pdf", text: $viewModel.addressList, axis: .vertical)
                        .textContentType(.URL)
                        .oneFeedURLKeyboard()
                        .oneFeedAutocapitalizationNever()
                        .autocorrectionDisabled()
                        .lineLimit(4...10)
                        .oneFeedSubmitGo()
                        .onSubmit { add() }
                } header: {
                    GallerySectionHeader(text: "Websites, articles, or files")
                } footer: {
                    Text("One per line. Feeds, articles, PDFs, and EPUBs can share a folder.")
                }
                .listRowBackground(OneFeedTheme.paper)

                Section {
                    Picker("Folder", selection: folderPickerSelection) {
                        Text("Unfiled").tag(FolderPick.unfiled)
                        ForEach(viewModel.availableFolders, id: \.self) { name in
                            Text(name).tag(FolderPick.existing(name))
                        }
                        Text("New Folder…").tag(FolderPick.createNew)
                    }
                    if viewModel.isCreatingNewFolder {
                        TextField("Must read, Builders…", text: $viewModel.newFolderName)
                            .oneFeedAutocapitalizationWords()
                    }
                } header: {
                    GallerySectionHeader(text: "Folder")
                } footer: {
                    Text("Same folder for every URL in this batch.")
                }
                .listRowBackground(OneFeedTheme.paper)

                if let progress = viewModel.progressLabel {
                    Section {
                        HStack(spacing: 12) {
                            OneFeedMarkPulse(isActive: true, size: 22)
                            Text(progress)
                                .foregroundStyle(OneFeedTheme.graphite)
                        }
                    }
                    .listRowBackground(OneFeedTheme.paper)
                }

                if let errorMessage = viewModel.presentedError {
                    Section { Text(errorMessage).foregroundStyle(OneFeedTheme.error) }
                        .listRowBackground(OneFeedTheme.paper)
                }
            }
            .overlay {
                ZStack {
                    if showSuccess {
                        OneFeedTheme.plaster.opacity(0.97)
                        VStack(spacing: 16) {
                            OneFeedMarkBurst(size: 56)
                            GalleryLabel(text: "Added")
                        }
                        .transition(.opacity)
                    }
                }
                .ignoresSafeArea()
                .animation(reduceMotion ? nil : OneFeedMotion.decision, value: showSuccess)
            }
            .navigationTitle(viewModel.addresses.count > 1 ? "Add Sources" : "Add Source")
            .oneFeedInlineTitle()
            .oneFeedPaperScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isAdding ? "Adding…" : "Add") { add() }
                        .disabled(viewModel.addresses.isEmpty || viewModel.isAdding || showSuccess)
                }
            }
            .sensoryFeedback(.success, trigger: showSuccess)
            .onAppear {
                viewModel.configureFolders(from: Array(feeds), preferred: preferredFolder)
                if let initialAddress, viewModel.addressList.isEmpty {
                    viewModel.addressList = initialAddress
                }
            }
        }
        .oneFeedMacFormSheet()
    }

    private var folderPickerSelection: Binding<FolderPick> {
        Binding(
            get: {
                if viewModel.isCreatingNewFolder { return .createNew }
                if viewModel.selectedFolder.isEmpty { return .unfiled }
                return .existing(viewModel.selectedFolder)
            },
            set: { pick in
                switch pick {
                case .unfiled:
                    viewModel.isCreatingNewFolder = false
                    viewModel.selectedFolder = ""
                case .existing(let name):
                    viewModel.isCreatingNewFolder = false
                    viewModel.selectedFolder = name
                case .createNew:
                    viewModel.isCreatingNewFolder = true
                    viewModel.selectedFolder = ""
                }
            }
        )
    }

    private func add() {
        Task {
            guard await viewModel.add(in: modelContext) else { return }
            onAdded()
            showSuccess = true
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(420))
            }
            // Stay open if the user might paste another batch; only dismiss when one batch succeeded cleanly.
            if viewModel.presentedError == nil {
                dismiss()
            } else {
                showSuccess = false
            }
        }
    }
}

private enum FolderPick: Hashable {
    case unfiled
    case existing(String)
    case createNew
}
