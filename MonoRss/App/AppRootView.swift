import SwiftUI

struct AppRootView: View {
    @AppStorage(AppPreferenceKey.completedOnboarding) private var completedOnboarding = false
    @State private var selectedTab: AppTab = .today

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Today", systemImage: "sun.max", value: .today) {
                NavigationStack {
                    CurrentView()
                }
            }
            Tab("Feed", systemImage: "list.bullet", value: .feed) {
                NavigationStack {
                    FeedStreamView()
                }
            }
            Tab("Saved", systemImage: "bookmark", value: .saved) {
                NavigationStack {
                    SavedView()
                }
            }
        }
        .tint(.primary)
        .fullScreenCover(isPresented: Binding(get: { !completedOnboarding }, set: { if !$0 { completedOnboarding = true } })) {
            OnboardingView { completedOnboarding = true }
        }
    }
}

private enum AppTab: Hashable {
    case today, feed, saved
}
