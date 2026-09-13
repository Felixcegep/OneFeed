import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppPreferenceKey.readerFont) private var readerFont = ReaderFontChoice.serif.rawValue
    @AppStorage(AppPreferenceKey.readerTextSize) private var readerTextSize = ReaderTextSize.standard.rawValue
    @AppStorage(AppPreferenceKey.articleRetentionDays) private var retentionDays = ArticleRetentionService.defaultRetentionDays
    @State private var viewModel = SettingsViewModel()
    @State private var geminiKey = ""
    @State private var library = LibrarySyncService.shared
    @State private var isPickingLibraryFolder = false
    @State private var isPickingLibraryFile = false

    var body: some View {
        Form {
            Section {
                Picker("Font", selection: $readerFont) { ForEach(ReaderFontChoice.allCases) { Text($0.label).tag($0.rawValue) } }
                Picker("Text Size", selection: $readerTextSize) { ForEach(ReaderTextSize.allCases) { Text($0.label).tag($0.rawValue) } }
            } header: {
                Text("Reading")
            } footer: {
                Text("Serif is the default for long articles. These choices apply in the reader.")
            }
            Section {
                Picker("Keep articles", selection: $retentionDays) {
                    ForEach(ArticleRetentionChoice.allCases) { choice in
                        Text(choice.label).tag(choice.rawValue)
                    }
                }
            } header: {
                Text("Library")
            } footer: {
                Text("Unread articles older than this are removed. Saved articles stay.")
            }
            Section {
                SecureField("AI Studio API key", text: $geminiKey)
                    .textContentType(.password)
                    .oneFeedAutocapitalizationNever()
                    .autocorrectionDisabled()
                    .onChange(of: geminiKey) { _, newValue in
                        GeminiAPIKeyStore.save(newValue)
                    }
                if !geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Remove key", role: .destructive) {
                        geminiKey = ""
                        GeminiAPIKeyStore.delete()
                    }
                }
            } header: {
                Text("Gemini")
            } footer: {
                Text("When you open a YouTube video, OneFeed asks before sending the link to Google AI Studio for a short summary.")
            }
            Section {
                if let account = viewModel.freshRSS {
                    LabeledContent("Account", value: account.username ?? "Connected")
                    LabeledContent("Last Sync", value: account.lastSyncAt?.formatted(date: .abbreviated, time: .shortened) ?? "Not yet")
                    if let error = account.lastSyncError { Text(error).font(.footnote).foregroundStyle(.red) }
                    Button {
                        Task { await viewModel.sync() }
                    } label: {
                        if viewModel.isSyncing {
                            Label {
                                Text("Syncing…")
                            } icon: {
                                OneFeedMarkPulse(isActive: true, size: 18)
                            }
                        } else {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }.disabled(viewModel.isSyncing)
                    Button("Reconnect", systemImage: "person.crop.circle.badge.checkmark") { viewModel.isConnectingFreshRSS = true }
                    Button("Disconnect FreshRSS", systemImage: "xmark.circle", role: .destructive) { viewModel.isConfirmingDisconnect = true }
                } else {
                    Button("Connect FreshRSS", systemImage: "server.rack") { viewModel.isConnectingFreshRSS = true }
                }
            } header: {
                Text("FreshRSS")
            } footer: {
                Text(viewModel.freshRSS == nil
                     ? "Bring your subscriptions and reading state into OneFeed."
                     : "Done and Save sync to FreshRSS. Skip stays in OneFeed, and follows your library folder if you chose one.")
            }
            Section {
                CloudLibrarySettingsSection(
                    library: library,
                    isBusy: viewModel.isLinkingGoogleDrive,
                    onChooseFolder: { isPickingLibraryFolder = true },
                    onChooseFile: { isPickingLibraryFile = true },
                    onLinkGoogleDrive: { viewModel.beginLinkGoogleDrive() },
                    onSyncNow: { Task { await library.syncNow() } },
                    onUnlink: { library.detach() },
                    onKeepThisDevice: { Task { _ = await library.sync(request: .keepThisIPhone) } },
                    onUseCloudFile: { Task { _ = await library.sync(request: .useCloudFile) } },
                    onSyncModeChange: { library.setSyncMode($0) }
                )
            } header: {
                Text("iCloud or Google Drive")
            } footer: {
                Text(library.footerText)
            }
            Section {
                Button("Restore all seeded sources", systemImage: "arrow.triangle.2.circlepath") {
                    viewModel.seedAllCatalogSources()
                }
                Button("Import OPML", systemImage: "square.and.arrow.down") { viewModel.isImportingOPML = true }
                Button("Export OPML", systemImage: "square.and.arrow.up") { viewModel.isExportingOPML = true }.disabled(viewModel.feeds.isEmpty)
            } header: {
                Text("Data")
            } footer: {
                Text("Restores Must read, Builders, topic folders, À scanner, and Papers — then fetches them. OPML import keeps folder names.")
            }
            Section("About") {
                LabeledContent("OneFeed", value: "1.0")
                Text("A reader for sources you chose.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .oneFeedInlineTitle()
        .refreshProgressBanner(viewModel.progress)
        .task {
            viewModel.configure(with: modelContext)
            library.configure(with: modelContext)
            geminiKey = GeminiAPIKeyStore.load() ?? ""
        }
        .sheet(isPresented: $viewModel.isConnectingFreshRSS, onDismiss: viewModel.reload) {
            FreshRSSConnectView(existingAccount: viewModel.freshRSS)
        }
        .confirmationDialog("Disconnect FreshRSS? Your locally stored articles will remain available.", isPresented: $viewModel.isConfirmingDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await viewModel.disconnect() } }
        }
        .fileImporter(isPresented: $isPickingLibraryFolder, allowedContentTypes: LibraryDocumentPicker.folderTypes) { result in
            Task {
                do { await library.attach(url: try result.get()) }
                catch { viewModel.statusMessage = error.localizedDescription }
            }
        }
        .fileImporter(isPresented: $isPickingLibraryFile, allowedContentTypes: LibraryDocumentPicker.fileTypes) { result in
            Task {
                do { await library.attach(url: try result.get()) }
                catch { viewModel.statusMessage = error.localizedDescription }
            }
        }
        .fileImporter(isPresented: $viewModel.isImportingOPML, allowedContentTypes: [.xml, UTType(filenameExtension: "opml") ?? .xml]) { result in
            do { viewModel.importOPML(from: try result.get()) }
            catch { viewModel.statusMessage = error.localizedDescription }
        }
        .fileExporter(isPresented: $viewModel.isExportingOPML, document: viewModel.exportDocument, contentType: .xml, defaultFilename: "OneFeed Sources.opml") { result in
            if case .failure(let error) = result { viewModel.statusMessage = error.localizedDescription }
        }
        .alert("OneFeed", isPresented: Binding(get: { viewModel.statusMessage != nil }, set: { if !$0 { viewModel.statusMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(viewModel.statusMessage ?? "") }
    }
}

private struct FreshRSSConnectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: FreshRSSConnectViewModel

    init(existingAccount: SyncAccount?) {
        _viewModel = State(initialValue: FreshRSSConnectViewModel(existingAccount: existingAccount))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://host:8081 or full …/api/greader.php URL", text: $viewModel.server)
                        .textContentType(.URL)
                        .oneFeedURLKeyboard()
                        .oneFeedAutocapitalizationNever()
                        .autocorrectionDisabled()
                    TextField("Username", text: $viewModel.username)
                        .textContentType(.username)
                        .oneFeedAutocapitalizationNever()
                        .autocorrectionDisabled()
                    SecureField("API password", text: $viewModel.apiPassword).textContentType(.password)
                } header: { Text("FreshRSS account") } footer: { Text("HTTP and HTTPS are both supported. You can paste either the server root or the full GReader API URL — both work. Credentials stay in the Keychain on this device.") }
                if let errorMessage = viewModel.presentedError { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("Connect FreshRSS")
            .oneFeedInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isConnecting {
                        OneFeedMarkPulse(isActive: true, size: 18)
                    } else {
                        Button("Connect") {
                            Task { if await viewModel.connect(in: modelContext) { dismiss() } }
                        }.disabled(viewModel.server.isEmpty || viewModel.username.isEmpty || viewModel.apiPassword.isEmpty)
                    }
                }
            }
        }
    }
}

struct GeminiAPIKeyForm: View {
    @Binding var key: String
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("AI Studio API key", text: $key)
                        .textContentType(.password)
                        .oneFeedAutocapitalizationNever()
                        .autocorrectionDisabled()
                } footer: {
                    Text("Create a key in Google AI Studio. It stays in the Keychain on this device.")
                }
            }
            .navigationTitle("Gemini")
            .oneFeedInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave() }
                        .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
    }
}
