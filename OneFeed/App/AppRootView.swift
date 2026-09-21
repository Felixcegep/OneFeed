import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppPreferenceKey.completedOnboarding) private var completedOnboarding = false
    @State private var selectedTab: AppTab = ProcessInfo.processInfo.arguments.contains("-uiTestingNotInterested") ? .feed : .today
    @State private var subscribeAddress: String?
    @State private var isPresentingSubscribe = false
    @State private var importError: String?
    @State private var isPickingDocument = false
    @State private var warmReaderWeb = false
    @State private var isLaunching = !ReaderWebWarmup.skipsOpeningCover
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsLaunchCover: Bool {
        isLaunching && !ReaderWebWarmup.skipsOpeningCover
    }

    var body: some View {
        root
            .tint(OneFeedTheme.ink)
            .onOpenURL(perform: handleIncomingURL)
            .sheet(isPresented: $isPresentingSubscribe, onDismiss: { subscribeAddress = nil }) {
                AddSourceView(initialAddress: subscribeAddress)
            }
            .oneFeedOnboardingCover(isPresented: Binding(get: { !completedOnboarding }, set: { if !$0 { completedOnboarding = true } })) {
                OnboardingView { completedOnboarding = true }
            }
            .overlay(alignment: .bottomLeading) {
                if warmReaderWeb {
                    ReaderWebProcessWarmup {
                        isLaunching = false
                    }
                }
            }
            .overlay {
                if showsLaunchCover {
                    OneFeedLoadingCover(
                        title: "OneFeed",
                        status: "Hanging the room…",
                        canvas: OneFeedTheme.plaster
                    )
                    .ignoresSafeArea()
                }
            }
            .animation(reduceMotion ? nil : OneFeedMotion.overlay, value: showsLaunchCover)
            .task {
                LibrarySyncService.shared.configure(with: modelContext)
                guard ReaderWebWarmup.isEnabled else {
                    isLaunching = false
                    return
                }
                warmReaderWeb = true
            }
            .onReceive(NotificationCenter.default.publisher(for: OneFeedNotify.subscribe)) { _ in
                isPresentingSubscribe = true
                selectedTab = .feed
            }
            .onReceive(NotificationCenter.default.publisher(for: OneFeedNotify.openFeed)) { _ in
                selectedTab = .feed
            }
            .onReceive(NotificationCenter.default.publisher(for: OneFeedNotify.openToday)) { _ in
                selectedTab = .today
            }
            .onReceive(NotificationCenter.default.publisher(for: OneFeedNotify.refresh)) { _ in
                Task { await BackgroundRefreshCoordinator.refresh(in: modelContext) }
            }
            .onReceive(NotificationCenter.default.publisher(for: OneFeedNotify.addToQueue)) { note in
                selectedTab = .queue
                if (note.userInfo?["pickFile"] as? Bool) == true {
                    isPickingDocument = true
                }
            }
            .fileImporter(
                isPresented: $isPickingDocument,
                allowedContentTypes: ImportedDocumentKind.readableTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task { await importIncomingDocuments(urls) }
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .alert("Couldn’t import", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
    }

    @ViewBuilder
    private var root: some View {
        #if os(macOS)
        MacRootView(selectedTab: $selectedTab)
        #else
        TabView(selection: $selectedTab) {
            Tab("Queue", systemImage: "square.stack", value: .queue) {
                NavigationStack {
                    SavedView()
                }
            }
            Tab("Feed", systemImage: "square.grid.2x2", value: .feed) {
                NavigationStack {
                    FoldersView()
                }
            }
            Tab("Today", systemImage: "sun.max", value: .today) {
                NavigationStack {
                    CurrentView()
                }
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        #endif
    }

    private func handleIncomingURL(_ url: URL) {
        if url.isFileURL, ImportedDocumentKind.infer(url: url) != nil {
            selectedTab = .queue
            Task { await importIncomingDocument(url) }
            return
        }
        guard let address = IncomingFeedURL.subscriptionAddress(from: url) else { return }
        subscribeAddress = address
        isPresentingSubscribe = true
        selectedTab = .feed
    }

    private func importIncomingDocument(_ url: URL) async {
        await importIncomingDocuments([url])
    }

    private func importIncomingDocuments(_ urls: [URL]) async {
        do {
            var last: Article?
            let service = ImportedDocumentService()
            for url in urls {
                last = try await service.importFile(at: url, in: modelContext)
            }
            if let last {
                QueueHandoff.pendingArticleID = last.id
                NotificationCenter.default.post(name: OneFeedNotify.openQueueArticle, object: last.id)
            }
        } catch {
            importError = error.localizedDescription
        }
    }
}

enum AppTab: Hashable {
    case queue, feed, today, settings
}

#if os(macOS)
private struct MacRootView: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section {
                    Label("Today", systemImage: "sun.max").tag(AppTab.today)
                    Label("Queue", systemImage: "square.stack").tag(AppTab.queue)
                    Label("Feed", systemImage: "square.grid.2x2").tag(AppTab.feed)
                }
                Section {
                    Label("Settings", systemImage: "gearshape").tag(AppTab.settings)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .alternatingRowBackgrounds(.disabled)
            .background(OneFeedTheme.warm1)
            .tint(OneFeedTheme.ink)
            .navigationTitle("OneFeed")
            .navigationSplitViewColumnWidth(min: 196, ideal: 220, max: 260)
        } detail: {
            Group {
                switch selectedTab {
                case .queue:
                    NavigationStack { SavedView() }
                case .feed:
                    NavigationStack { FoldersView() }
                case .today:
                    NavigationStack { CurrentView() }
                case .settings:
                    NavigationStack { SettingsView() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OneFeedTheme.plaster)
        }
        .navigationSplitViewStyle(.balanced)
        .oneFeedWindowPlaster()
    }
}
#endif
