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
                settingsLink("Reading", summary: "\(ReaderFontChoice(rawValue: readerFont)?.label ?? "Serif") · \(ReaderTextSize(rawValue: readerTextSize)?.label ?? "Default")") {
                    readingSection
                }
                settingsLink("Sources & Import", summary: "Subscriptions and OPML") {
                    sourcesSection
                }
                settingsLink("Sync", summary: "FreshRSS, iCloud or Google Drive") {
                    freshRSSSection
                    cloudSection
                }
                settingsLink("Storage", summary: "Keep articles · \(ArticleRetentionChoice(rawValue: retentionDays)?.label ?? "\(retentionDays) days")") {
                    storageSection
                }
                settingsLink("Video summaries", summary: geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Not configured" : "API key configured") {
                    videoSection
                }
                settingsLink("About", summary: "OneFeed · 1.0") {
                    aboutSection
                }
            }
            .listRowBackground(OneFeedTheme.paper)
        }
        .navigationTitle("Settings")
        .oneFeedInlineTitle()
        .scrollContentBackground(.hidden)
        .background(OneFeedTheme.plaster)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 96)
        }
        .tint(OneFeedTheme.ink)
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

    private var readingSection: some View {
        Section {
            ReadingAppearancePreview(
                fontChoice: ReaderFontChoice(rawValue: readerFont) ?? .serif,
                textSize: ReaderTextSize(rawValue: readerTextSize) ?? .standard
            )
            Picker("Font", selection: $readerFont) { ForEach(ReaderFontChoice.allCases) { Text($0.label).tag($0.rawValue) } }
            Picker("Text Size", selection: $readerTextSize) { ForEach(ReaderTextSize.allCases) { Text($0.label).tag($0.rawValue) } }
        } footer: {
            Text("Serif is the default for long articles. These choices apply in the reader.")
                .foregroundStyle(OneFeedTheme.graphite)
        }
        .listRowBackground(OneFeedTheme.paper)
    }

    private var storageSection: some View {
        Section {
            Picker("Keep articles", selection: $retentionDays) {
                ForEach(ArticleRetentionChoice.allCases) { choice in
                    Text(choice.label).tag(choice.rawValue)
                }
            }
        } header: {
            GallerySectionHeader(text: "Library")
        } footer: {
            Text("Unread articles older than this are removed. Items in Queue stay.")
                .foregroundStyle(OneFeedTheme.graphite)
        }
        .listRowBackground(OneFeedTheme.paper)
    }

    private var cloudSection: some View {
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
            GallerySectionHeader(text: "iCloud or Google Drive")
        } footer: {
            Text(library.footerText)
                .foregroundStyle(OneFeedTheme.graphite)
        }
        .listRowBackground(OneFeedTheme.paper)
    }

    private var videoSection: some View {
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
            GallerySectionHeader(text: "Gemini")
        } footer: {
            Text("When you open a YouTube video, OneFeed asks before sending the link to Google AI Studio for a short summary.")
                .foregroundStyle(OneFeedTheme.graphite)
        }
        .listRowBackground(OneFeedTheme.paper)
    }

    private var freshRSSSection: some View {
        Section {
            if let account = viewModel.freshRSS {
                settingsValue("Account", value: account.username ?? "Connected")
                settingsValue("Last Sync", value: account.lastSyncAt?.formatted(date: .abbreviated, time: .shortened) ?? "Not yet")
                if let error = account.lastSyncError { Text(error).font(.footnote).foregroundStyle(OneFeedTheme.error) }
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
            GallerySectionHeader(text: "FreshRSS")
        } footer: {
            Text(viewModel.freshRSS == nil
                 ? "Bring your subscriptions and reading state into OneFeed."
                 : "Done and Save sync to FreshRSS. Skip stays in OneFeed, and follows your library folder if you chose one.")
                .foregroundStyle(OneFeedTheme.graphite)
        }
        .listRowBackground(OneFeedTheme.paper)
    }

    private var sourcesSection: some View {
        Section {
            NavigationLink {
                SourcesView()
            } label: {
                Label("Manage sources", systemImage: "dot.radiowaves.left.and.right")
            }
            Button("Restore all seeded sources", systemImage: "arrow.triangle.2.circlepath") {
                viewModel.seedAllCatalogSources()
            }
            Button("Import OPML", systemImage: "square.and.arrow.down") { viewModel.isImportingOPML = true }
            Button("Export OPML", systemImage: "square.and.arrow.up") { viewModel.isExportingOPML = true }.disabled(viewModel.feeds.isEmpty)
        } header: {
            GallerySectionHeader(text: "Data")
        } footer: {
            Text("Restores Must read, Builders, topic folders, À scanner, and Papers — then fetches them. OPML import keeps folder names.")
                .foregroundStyle(OneFeedTheme.graphite)
        }
        .listRowBackground(OneFeedTheme.paper)
    }

    private var aboutSection: some View {
        Section {
            OneFeedBrandLockup(markSize: 52, showsTagline: true)
                .padding(.vertical, 18)
            settingsValue("Edition", value: "1.0")
        } header: {
            GallerySectionHeader(text: "About")
        }
        .listRowBackground(OneFeedTheme.paper)
    }

    private func settingsLink<Content: View>(
        _ title: String,
        summary: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        NavigationLink {
            Form {
                content()
            }
            .navigationTitle(title)
            .oneFeedInlineTitle()
            .scrollContentBackground(.hidden)
            .background(OneFeedTheme.plaster)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 96)
            }
            .tint(OneFeedTheme.ink)
            .refreshProgressBanner(viewModel.progress)
            .onAppear { viewModel.reload() }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(OneFeedTheme.ink)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(OneFeedTheme.graphite)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func settingsValue(_ title: String, value: String) -> some View {
        StackedLabeledValue(title: title, value: value)
    }
}

private struct ReadingAppearancePreview: View {
    let fontChoice: ReaderFontChoice
    let textSize: ReaderTextSize
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var design: Font.Design {
        switch fontChoice {
        case .sans: .default
        case .serif: .serif
        case .mono: .monospaced
        }
    }

    private var pointSize: CGFloat { textSize.points }

    var body: some View {
        Text("One article at a time. The rest of the room stays quiet.")
            .font(.system(size: pointSize, design: design))
            .lineSpacing(pointSize * 0.55)
            .foregroundStyle(OneFeedTheme.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .accessibilityLabel("Reading preview")
            .accessibilityValue("One article at a time. The rest of the room stays quiet.")
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
                } header: {
                    GallerySectionHeader(text: "FreshRSS account")
                } footer: {
                    Text("HTTP and HTTPS are both supported. You can paste either the server root or the full GReader API URL — both work. Credentials stay in the Keychain on this device.")
                        .foregroundStyle(OneFeedTheme.graphite)
                }
                .listRowBackground(OneFeedTheme.paper)
                if let errorMessage = viewModel.presentedError {
                    Section {
                        Text(errorMessage).foregroundStyle(OneFeedTheme.error)
                    }
                    .listRowBackground(OneFeedTheme.paper)
                }
            }
            .navigationTitle("Connect FreshRSS")
            .oneFeedInlineTitle()
            .oneFeedPaperScreen()
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
    #if os(iOS)
    @State private var sheetDetent: PresentationDetent = .medium
    @FocusState private var keyFieldFocused: Bool
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("AI Studio API key", text: $key)
                        .textContentType(.password)
                        .oneFeedAutocapitalizationNever()
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .focused($keyFieldFocused)
                        #endif
                } footer: {
                    Text("Create a key in Google AI Studio. It stays in the Keychain on this device.")
                        .foregroundStyle(OneFeedTheme.graphite)
                }
                .listRowBackground(OneFeedTheme.paper)
            }
            .navigationTitle("Gemini")
            .oneFeedInlineTitle()
            .oneFeedPaperScreen()
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
        .presentationDetents([.medium, .large], selection: $sheetDetent)
        .presentationContentInteraction(.scrolls)
        .onChange(of: keyFieldFocused) { _, focused in
            if focused { sheetDetent = .large }
        }
        #endif
    }
}
