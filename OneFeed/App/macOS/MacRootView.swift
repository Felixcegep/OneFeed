#if os(macOS)
import SwiftUI

struct MacRootView: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section {
                    Label("Today", systemImage: "sun.max").tag(AppTab.today)
                    Label("Queue", systemImage: "square.stack").tag(AppTab.queue)
                    Label("Feed", systemImage: "square.grid.2x2").tag(AppTab.feed)
                }
                Section {
                    Label("Settings", systemImage: "gearshape").tag(AppTab.settings)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .alternatingRowBackgrounds(.disabled)
            .background(OneFeedTheme.warm1)
            .tint(OneFeedTheme.ink)
            .navigationTitle("OneFeed")
            .navigationSplitViewColumnWidth(min: 196, ideal: 220, max: 260)
        } detail: {
            AppTabRoot(tab: selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(OneFeedTheme.plaster)
        }
        .navigationSplitViewStyle(.balanced)
        .oneFeedWindowPlaster()
    }
}
#endif
