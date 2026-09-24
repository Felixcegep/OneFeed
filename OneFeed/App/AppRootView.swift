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
                AddSourceView(initialAddress: subscribeAddress, onAdded: {
                    Task { await BackgroundRefreshCoordinator.refresh(in: modelContext) }
                })
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
                    importError = UserFacingFailure.message(for: error, fallback: "Couldn’t import that file.")
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
        AppShell(selectedTab: $selectedTab)
    }

    private func handleIncomingURL(_ url: URL) {
        if ImportedDocumentKind.infer(url: url) != nil {
            selectedTab = .queue
            Task {
                if url.isFileURL {
                    await importIncomingDocument(url)
                } else {
                    await importRemoteDocument(url)
                }
            }
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

    private func importRemoteDocument(_ url: URL) async {
        do {
            let article = try await ImportedDocumentService().importRemote(url: url, in: modelContext)
            QueueHandoff.pendingArticleID = article.id
            NotificationCenter.default.post(name: OneFeedNotify.openQueueArticle, object: article.id)
        } catch {
            importError = UserFacingFailure.message(for: error, fallback: "Couldn’t import that file.")
        }
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
            importError = UserFacingFailure.message(for: error, fallback: "Couldn’t import that file.")
        }
    }
}
