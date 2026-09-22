import SwiftUI

enum AppTab: Hashable {
    case queue, feed, today, settings
}

/// The four sections. Compact width shows them as tabs; a wide window shows them as a sidebar.
struct AppTabRoot: View {
    let tab: AppTab

    var body: some View {
        switch tab {
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
}
