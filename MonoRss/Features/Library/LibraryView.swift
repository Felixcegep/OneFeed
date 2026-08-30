import SwiftUI

struct LibraryView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    SourcesView()
                } label: {
                    Label("Sources", systemImage: "dot.radiowaves.left.and.right")
                }
                NavigationLink {
                    HistoryView()
                } label: {
                    Label("History", systemImage: "clock")
                }
            }
            Section {
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .navigationTitle("Library")
    }
}
