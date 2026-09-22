import SwiftUI

/// Shared iPhone and Mac shell. The system keeps a tab bar in a compact width
/// and switches to a sidebar when there is room, including a resizable iPhone.
struct AppShell: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        TabView(selection: $selectedTab) {
            TabSection {
                Tab("Queue", systemImage: "square.stack", value: AppTab.queue) {
                    AppTabRoot(tab: .queue)
                }
                Tab("Feed", systemImage: "square.grid.2x2", value: AppTab.feed) {
                    AppTabRoot(tab: .feed)
                }
                Tab("Today", systemImage: "sun.max", value: AppTab.today) {
                    AppTabRoot(tab: .today)
                }
            } header: {
                EmptyView()
            }
            TabSection {
                Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                    AppTabRoot(tab: .settings)
                }
            } header: {
                EmptyView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .oneFeedPreferredSidebar()
        .tabViewSidebarHeader {
            Text("OneFeed")
                .font(OneFeedTheme.sansUI(17, weight: .semibold))
                .foregroundStyle(OneFeedTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .oneFeedWindowPlaster()
    }
}
