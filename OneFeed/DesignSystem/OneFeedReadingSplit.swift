import SwiftUI

/// Mac reading window: the list stays in a column, the story fills the rest.
/// iPhone keeps the full-screen cover.
struct OneFeedReadingSplit<Sidebar: View, Reader: View>: View {
    @Binding var article: Article?
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var reader: (Article) -> Reader

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            sidebar()
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 420)
        } detail: {
            if let article {
                reader(article)
                    .id(article.id)
            } else {
                MacReadingPlaceholder()
            }
        }
        .navigationSplitViewStyle(.balanced)
        #else
        sidebar()
            .oneFeedArticleCover(item: $article, content: reader)
        #endif
    }
}

private struct MacReadingPlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("The story opens here")
                .font(OneFeedTheme.serifDisplay(28))
                .oneFeedLegibleWeight()
                .foregroundStyle(OneFeedTheme.ink)
                .multilineTextAlignment(.center)
            Text("Pick one from the list. This side of the window stays put.")
                .font(.body)
                .foregroundStyle(OneFeedTheme.graphite)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OneFeedTheme.plaster)
    }
}
