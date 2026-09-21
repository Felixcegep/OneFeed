#if os(iOS)
import SwiftUI

struct PhoneRootView: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Queue", systemImage: "square.stack", value: .queue) {
                AppTabRoot(tab: .queue)
            }
            Tab("Feed", systemImage: "square.grid.2x2", value: .feed) {
                AppTabRoot(tab: .feed)
            }
            Tab("Today", systemImage: "sun.max", value: .today) {
                AppTabRoot(tab: .today)
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                AppTabRoot(tab: .settings)
            }
        }
    }
}
#endif
