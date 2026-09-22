import SwiftData
import SwiftUI

struct SourcesView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SourcesViewModel()
    @State private var addPreferredFolder: String?
    @State private var pickingFolder: FolderIconTarget?
    @State private var iconTick = 0
    @State private var searchText = ""
    @State private var folderToRemove: String?

    private var visibleFolders: [FeedFolderGroup] {
        guard !searchText.isEmpty else { return viewModel.folders }
        return viewModel.folders.filter { folder in
            folder.name.localizedStandardContains(searchText)
                || folder.feeds.contains { $0.title.localizedStandardContains(searchText) }
        }
    }

    var body: some View {
        let _ = iconTick
        List {
            if visibleFolders.isEmpty {
                Section {
                    if searchText.isEmpty {
                        ContentUnavailableView {
                            Label("No folders yet", systemImage: "folder")
                        } description: {
                            Text("Add a source or create a folder to organize your reading.")
                        } actions: {
                            Button("Add Source") { presentAdd() }
                                .buttonStyle(.borderedProminent)
                        }
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
                .listRowBackground(OneFeedTheme.paper)
            } else {
                if visibleFolders.contains(where: { !$0.feeds.isEmpty }) {
                    Section("With sources") {
                        ForEach(visibleFolders.filter { !$0.feeds.isEmpty }) { folder in
                            folderLink(folder)
                        }
                    }
                }
                if visibleFolders.contains(where: { $0.feeds.isEmpty }) {
                    Section("Empty folders") {
                        ForEach(visibleFolders.filter { $0.feeds.isEmpty }) { folder in
                            folderLink(folder)
                        }
                    }
                }
            }
        }
        .oneFeedGroupedListStyle()
        .searchable(text: $searchText, prompt: "Folders or sources")
        .navigationTitle("Sources")
        .oneFeedLargeTitle()
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
            viewModel.reload()
        }) {
            AddSourceView(preferredFolder: addPreferredFolder)
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
        .alert("OneFeed", isPresented: Binding(
            get: { viewModel.statusMessage != nil },
            set: { if !$0 { viewModel.statusMessage = nil } }
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

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.body)
                    .foregroundStyle(OneFeedTheme.ink)
                    .lineLimit(1)
                if let preview {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(OneFeedTheme.graphite)
                        .lineLimit(2)
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
    @State private var searchText = ""

    private var visibleFeeds: [Feed] {
        let feeds = viewModel.feeds(in: folderID)
        guard !searchText.isEmpty else { return feeds }
        return feeds.filter {
            $0.title.localizedStandardContains(searchText)
                || $0.feedURL.absoluteString.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        List {
            if visibleFeeds.isEmpty {
                Section {
                    if searchText.isEmpty {
                        ContentUnavailableView {
                            Label("No sources yet", systemImage: "dot.radiowaves.left.and.right")
                        } description: {
                            Text("Add a source to start filling this folder.")
                        } actions: {
                            Button("Add Source") { onAddInFolder() }
                                .buttonStyle(.borderedProminent)
                        }
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
                .listRowBackground(OneFeedTheme.paper)
            } else {
            Section {
                ForEach(visibleFeeds) { feed in
                    NavigationLink {
                        SourceDetailView(feed: feed, context: modelContext)
                    } label: {
                        SourceRow(feed: feed)
                    }
                    .sourceManageRow()
                    .contextMenu {
                        Menu("Move to Folder") {
                            Button("Unfiled") { viewModel.move(feed, to: nil) }
                            ForEach(viewModel.folderNames, id: \.self) { name in
                                Button(name) { viewModel.move(feed, to: name) }
                            }
                        }
                    }
                }
            }
            }
        }
        .oneFeedGroupedListStyle()
        .searchable(text: $searchText, prompt: "Sources in this folder")
        .navigationTitle(folderID.title)
        .oneFeedLargeTitle()
        .toolbar {
            ToolbarItem(placement: .oneFeedTrailing) {
                Button("Add Source", systemImage: "plus") { onAddInFolder() }
            }
        }
    }
}

private struct SourceRow: View {
    let feed: Feed

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
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(OneFeedTheme.graphite)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityHint(feed.isEnabled ? "Opens source details" : "Paused. Opens source details")
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
                Picker("Folder", selection: $viewModel.folderSelection) {
                    Text("Unfiled").tag("")
                    ForEach(viewModel.availableFolders, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                Button("New Folder…") { isCreatingFolder = true }
            } footer: {
                Text("Folders keep Must read separate from skim noise.")
            }
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
            if viewModel.feed.refreshesOverRSS {
                Section {
                    TextField("AI, Sponsored…", text: $viewModel.blockedWords, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Blocked words")
                } footer: {
                    Text("Comma or new-line separated. Matching items never enter Today or Feed.")
                }
            }
            if !viewModel.recentArticles.isEmpty {
                Section(viewModel.feed.refreshesOverRSS ? "Recent" : "Read") {
                    ForEach(viewModel.recentArticles) { article in
                        Button {
                            selectedArticle = article
                        } label: {
                            ArticleRow(article: article)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Section {
                Button("Remove Source", role: .destructive) { viewModel.isConfirmingRemoval = true }
            }
        }
        .navigationTitle(viewModel.feed.title)
        .oneFeedInlineTitle()
        .oneFeedPaperScreen()
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
            Button("Move Here") {
                let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                FolderStore.remember(name)
                viewModel.reloadFolders()
                viewModel.folderSelection = name
                newFolderName = ""
            }
        }
        .confirmationDialog("Remove this source and its locally stored articles?", isPresented: $viewModel.isConfirmingRemoval, titleVisibility: .visible) {
            Button("Remove Source", role: .destructive) {
                dismiss()
                Task { @MainActor in await viewModel.remove() }
            }
        }
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

    var preferredFolder: String?
    /// Prefills the address field (e.g. from a `feed:` / Share / deep link).
    var initialAddress: String? = nil

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
                    Text("Websites, articles, or files")
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
                    Text("Folder")
                } footer: {
                    Text("Same folder for every URL in this batch.")
                }
                .listRowBackground(OneFeedTheme.paper)

                if let progress = viewModel.progressLabel {
                    Section {
                        HStack(spacing: 12) {
                            OneFeedMarkPulse(isActive: true, size: 22)
                            Text(progress)
                                .foregroundStyle(.secondary)
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
                if showSuccess {
                    ZStack {
                        OneFeedTheme.plaster.opacity(0.97)
                        VStack(spacing: 16) {
                            OneFeedMarkBurst(size: 56)
                            GalleryLabel(text: "Added")
                        }
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)
                }
            }
            .animation(OneFeedMotion.decision, value: showSuccess)
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
