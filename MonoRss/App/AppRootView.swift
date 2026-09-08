import SwiftUI

struct AppRootView: View {
    @AppStorage(AppPreferenceKey.completedOnboarding) private var completedOnboarding = false
    @State private var selectedTab: AppTab = .today
    @State private var subscribeAddress: String?
    @State private var isPresentingSubscribe = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Today", systemImage: "sun.max", value: .today) {
                NavigationStack {
                    CurrentView()
                }
            }
            Tab("Feed", systemImage: "list.bullet", value: .feed) {
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
        .tint(OneFeedTheme.accent)
        .onOpenURL(perform: handleIncomingURL)
        .sheet(isPresented: $isPresentingSubscribe, onDismiss: { subscribeAddress = nil }) {
            AddSourceView(initialAddress: subscribeAddress)
        }
        .fullScreenCover(isPresented: Binding(get: { !completedOnboarding }, set: { if !$0 { completedOnboarding = true } })) {
            OnboardingView { completedOnboarding = true }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard let address = IncomingFeedURL.subscriptionAddress(from: url) else { return }
        subscribeAddress = address
        isPresentingSubscribe = true
        selectedTab = .feed
    }
}

private enum AppTab: Hashable {
    case today, feed, saved
}
