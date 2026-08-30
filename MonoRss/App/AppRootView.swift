import SwiftUI

struct AppRootView: View {
    @AppStorage(AppPreferenceKey.completedOnboarding) private var completedOnboarding = false
    @State private var selectedTab: AppTab = .recent

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Recent", systemImage: "clock", value: .recent) {
                NavigationStack {
                    RecentView()
                }
            }
            Tab("Feeds", systemImage: "folder", value: .folders) {
                NavigationStack {
                    FoldersView()
                }
            }
            Tab("Next", systemImage: "text.alignleft", value: .next) {
                NavigationStack {
                    CurrentView {
                        selectedTab = .library
                    }
                }
            }
            Tab("Saved", systemImage: "bookmark", value: .saved) {
                NavigationStack {
                    SavedView()
                }
            }
            Tab("Library", systemImage: "square.grid.2x2", value: .library) {
                NavigationStack {
                    LibraryView()
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
    case recent, folders, next, saved, library
}
