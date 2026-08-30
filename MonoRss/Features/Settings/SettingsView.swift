import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppPreferenceKey.readerFont) private var readerFont = ReaderFontChoice.sans.rawValue
    @AppStorage(AppPreferenceKey.readerTextSize) private var readerTextSize = ReaderTextSize.standard.rawValue
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        Form {
            Section {
                Picker("Font", selection: $readerFont) { ForEach(ReaderFontChoice.allCases) { Text($0.label).tag($0.rawValue) } }
                Picker("Text Size", selection: $readerTextSize) { ForEach(ReaderTextSize.allCases) { Text($0.label).tag($0.rawValue) } }
            } header: {
                Text("Reading")
            } footer: {
                Text("These choices apply to the in-app reader.")
            }
            Section {
                if let account = viewModel.freshRSS {
                    LabeledContent("Account", value: account.username ?? "Connected")
                    LabeledContent("Last Sync", value: account.lastSyncAt?.formatted(date: .abbreviated, time: .shortened) ?? "Not yet")
                    if let error = account.lastSyncError { Text(error).font(.footnote).foregroundStyle(.red) }
                    Button(viewModel.isSyncing ? "Syncing…" : "Sync Now", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await viewModel.sync() }
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
                     ? "Bring your subscriptions and reading state into OneFeed while keeping the one-article experience."
                     : "Done and Save sync to FreshRSS. Skip stays on this device.")
            }
            Section {
                Button("Import OPML", systemImage: "square.and.arrow.down") { viewModel.isImportingOPML = true }
                Button("Export OPML", systemImage: "square.and.arrow.up") { viewModel.isExportingOPML = true }.disabled(viewModel.feeds.isEmpty)
            } header: {
                Text("Data")
            } footer: {
                Text("Imported sources are fetched immediately so they can enter the queue.")
            }
            Section("About") {
                LabeledContent("OneFeed", value: "1.0")
                Text("One article at a time.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { viewModel.configure(with: modelContext) }
        .sheet(isPresented: $viewModel.isConnectingFreshRSS, onDismiss: viewModel.reload) {
            FreshRSSConnectView(existingAccount: viewModel.freshRSS)
        }
        .confirmationDialog("Disconnect FreshRSS? Your locally stored articles will remain available.", isPresented: $viewModel.isConfirmingDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await viewModel.disconnect() } }
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
                    TextField("http://rss.local or https://rss.example.com", text: $viewModel.server).textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Username", text: $viewModel.username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("API password", text: $viewModel.apiPassword).textContentType(.password)
                } header: { Text("FreshRSS account") } footer: { Text("HTTP and HTTPS are both supported. Create an API password in your FreshRSS profile. It is stored only in the iOS Keychain.") }
                if let errorMessage = viewModel.presentedError { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("Connect FreshRSS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isConnecting ? "Connecting…" : "Connect") {
                        Task { if await viewModel.connect(in: modelContext) { dismiss() } }
                    }.disabled(viewModel.server.isEmpty || viewModel.username.isEmpty || viewModel.apiPassword.isEmpty || viewModel.isConnecting)
                }
            }
        }
    }
}
