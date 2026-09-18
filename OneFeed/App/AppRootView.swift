import SwiftUI
import SwiftData

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppPreferenceKey.completedOnboarding) private var completedOnboarding = false
    @State private var selectedTab: AppTab = .today
    @State private var subscribeAddress: String?
    @State private var isPresentingSubscribe = false
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
        guard let address = IncomingFeedURL.subscriptionAddress(from: url) else { return }
        subscribeAddress = address
        isPresentingSubscribe = true
        selectedTab = .feed
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
                    Label("Queue", systemImage: "square.stack").tag(AppTab.queue)
                    Label("Feed", systemImage: "square.grid.2x2").tag(AppTab.feed)
                    Label("Today", systemImage: "sun.max").tag(AppTab.today)
                }
                Section {
                    Label("Settings", systemImage: "gearshape").tag(AppTab.settings)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("OneFeed")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                OneFeedBrandLockup(markSize: 28, showsTagline: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
            }
            .navigationSplitViewColumnWidth(min: 196, ideal: 216, max: 260)
        } detail: {
            NavigationStack {
                switch selectedTab {
                case .queue: SavedView()
                case .feed: FoldersView()
                case .today: CurrentView()
                case .settings: SettingsView()
                }
            }
            .background(OneFeedTheme.plaster)
        }
        .navigationSplitViewStyle(.balanced)
    }
}
#endif
