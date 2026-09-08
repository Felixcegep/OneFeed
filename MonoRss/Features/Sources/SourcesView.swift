import SwiftData
import SwiftUI

struct SourcesView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SourcesViewModel()
    @State private var addPreferredFolder: String?

    var body: some View {
        Group {
            if viewModel.feeds.isEmpty && viewModel.folders.isEmpty {
                ContentUnavailableView {
                    Label("No sources", systemImage: "dot.radiowaves.left.and.right")
                } description: {
                    Text("Add feeds one by one, paste a list, or restore the full seeded library with folders.")
                } actions: {
                    Button("Add Sources") { presentAdd() }
                        .buttonStyle(.borderedProminent)
                    Button("Restore all seeded sources") { viewModel.importAllSeededSources() }
                        .buttonStyle(.bordered)
                }
            } else {
                List {
                    ForEach(viewModel.folders) { folder in
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
                        .accessibilityIdentifier("folder-\(folder.name)")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Sources")
        .navigationBarTitleDisplayMode(.inline)
        .task { viewModel.configure(with: modelContext) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add Sources", systemImage: "plus") { presentAdd() }
                    Button("New Folder", systemImage: "folder.badge.plus") {
                        viewModel.newFolderName = ""
                        viewModel.isPresentingNewFolder = true
                    }
                    Divider()
                    Button("Restore all seeded sources", systemImage: "arrow.triangle.2.circlepath") {
                        viewModel.importAllSeededSources()
                    }
                    .disabled(viewModel.isImportingPack)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add")
            }
        }
        .sheet(isPresented: $viewModel.isPresentingAddSource, onDismiss: {
            addPreferredFolder = nil
            viewModel.reload()
        }) {
            AddSourceView(preferredFolder: addPreferredFolder)
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
    }

    private func presentAdd(folder: String? = nil) {
        addPreferredFolder = folder
        viewModel.isPresentingAddSource = true
    }
}

private struct FolderRow: View {
    let folder: FeedFolderGroup

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "folder")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(folder.name)
                    .font(.headline)
                Text(sourceCount)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens feeds in this folder")
    }

    private var sourceCount: String {
        switch folder.feeds.count {
        case 0: "Empty · add sources"
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

    var body: some View {
        List {
            ForEach(viewModel.feeds(in: folderID)) { feed in
                NavigationLink {
                    SourceDetailView(feed: feed, context: modelContext)
                } label: {
                    SourceRow(feed: feed)
                }
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
        .listStyle(.insetGrouped)
        .navigationTitle(folderID.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add", systemImage: "plus") { onAddInFolder() }
            }
        }
        .overlay {
            if viewModel.feeds(in: folderID).isEmpty {
                ContentUnavailableView {
                    Label("No feeds", systemImage: "dot.radiowaves.left.and.right")
                } description: {
                    Text("Add sources directly into \(folderID.title).")
                } actions: {
                    Button("Add Sources") { onAddInFolder() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

private struct SourceRow: View {
    let feed: Feed

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(feed.title)
                .font(.headline)
            HStack(spacing: 5) {
                Text(feed.websiteURL?.host() ?? feed.feedURL.host() ?? feed.feedURL.absoluteString)
                    .lineLimit(1)
                if !feed.isEnabled {
                    Text("·")
                    Text("Paused")
                } else if feed.remoteID != nil {
                    Text("·")
                    Text("Synced")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityHint(feed.isEnabled ? "Opens source details" : "Paused. Opens source details")
    }
}

private struct SourceDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SourceDetailViewModel
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""

    init(feed: Feed, context: ModelContext) {
        _viewModel = State(initialValue: SourceDetailViewModel(feed: feed, context: context))
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Website", value: viewModel.feed.websiteURL?.host() ?? "—")
                LabeledContent("Feed", value: viewModel.feed.feedURL.absoluteString)
            }
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
                Toggle("Include videos", isOn: $viewModel.includeVideos)
                Toggle("Include Shorts", isOn: $viewModel.includeShorts)
            } footer: {
                Text("Today is a small daily stack. Videos shorter than 3 minutes are skipped unless you allow Shorts.")
            }
            Section {
                TextField("AI, Sponsored…", text: $viewModel.blockedWords, axis: .vertical)
                    .lineLimit(2...4)
            } header: {
                Text("Blocked words")
            } footer: {
                Text("Comma or new-line separated. Matching items never enter Today or Feed.")
            }
            if !viewModel.recentArticles.isEmpty {
                Section("Recent") {
                    ForEach(viewModel.recentArticles) { article in
                        ArticleRow(article: article)
                    }
                }
            }
            Section {
                Button("Remove Source", role: .destructive) { viewModel.isConfirmingRemoval = true }
            }
        }
        .navigationTitle(viewModel.feed.title)
        .navigationBarTitleDisplayMode(.inline)
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
                    TextField("example.com\nsecond.com/feed", text: $viewModel.addressList, axis: .vertical)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(4...10)
                        .submitLabel(.go)
                        .onSubmit { add() }
                } header: {
                    Text("Websites or RSS URLs")
                } footer: {
                    Text("One per line. Paste several to add them all into the same folder.")
                }

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
                            .textInputAutocapitalization(.words)
                    }
                } header: {
                    Text("Folder")
                } footer: {
                    Text("Same folder for every URL in this batch.")
                }

                if let progress = viewModel.progressLabel {
                    Section {
                        HStack(spacing: 12) {
                            OneFeedMarkPulse(isActive: true, size: 22)
                            Text(progress)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let errorMessage = viewModel.presentedError {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .overlay {
                if showSuccess {
                    OneFeedMarkBurst(size: 48)
                        .transition(.opacity)
                }
            }
            .navigationTitle(viewModel.addresses.count > 1 ? "Add Sources" : "Add Source")
            .navigationBarTitleDisplayMode(.inline)
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
