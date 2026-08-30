import SwiftUI

struct AppRootView: View {
    @AppStorage(AppPreferenceKey.completedOnboarding) private var completedOnboarding = false
    @State private var viewModel = AppRootViewModel()

    var body: some View {
        NavigationStack(path: $viewModel.path) {
            CurrentView { viewModel.open($0) }
                .navigationDestination(for: AppDestination.self) { destination in
                    switch destination {
                    case .saved: SavedView()
                    case .history: HistoryView()
                    case .sources: SourcesView()
                    case .settings: SettingsView()
                    }
                }
        }
        .tint(.primary)
        .fullScreenCover(isPresented: Binding(get: { !completedOnboarding }, set: { if !$0 { completedOnboarding = true } })) {
            OnboardingView { completedOnboarding = true }
        }
    }
}
