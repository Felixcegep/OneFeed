import SwiftUI
import SwiftData

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppPreferenceKey.completedOnboarding) private var completedOnboarding = false
    @State private var selectedTab: AppTab = .today
    @State private var subscribeAddress: String?
    @State private var isPresentingSubscribe = false

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
            .task {
                LibrarySyncService.shared.configure(with: modelContext)
            }
            .onReceive(NotificationCenter.default.publisher(for: OneFeedNotify.subscribe)) { _ in
                isPresentingSubscribe = true
                selectedTab = .feed
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
            Tab("Today", systemImage: "sun.max", value: .today) {
                NavigationStack {
                    CurrentView()
                }
            }
            Tab("Feed", systemImage: "square.grid.2x2", value: .feed) {
                NavigationStack {
                    FoldersView()
                }
            }
            Tab("Saved", systemImage: "star", value: .saved) {
                NavigationStack {
                    SavedView()
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
    case today, feed, saved, settings
}

#if os(macOS)
private struct MacRootView: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section {
                    Label("Today", systemImage: "sun.max").tag(AppTab.today)
                    Label("Feed", systemImage: "square.grid.2x2").tag(AppTab.feed)
                    Label("Saved", systemImage: "star").tag(AppTab.saved)
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
                case .today: CurrentView()
                case .feed: FoldersView()
                case .saved: SavedView()
                case .settings: SettingsView()
                }
            }
            .background(OneFeedTheme.plaster)
        }
        .navigationSplitViewStyle(.balanced)
    }
}
#endif
