import SwiftUI
import WebKit

struct ArticleBrowserView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var page: WebPage

    init(url: URL) {
        self.url = url
        var configuration = WebPage.Configuration()
        configuration.loadsSubresources = true
        configuration.defaultNavigationPreferences.allowsContentJavaScript = true
        _page = State(initialValue: WebPage(configuration: configuration))
    }

    var body: some View {
        NavigationStack {
            WebView(page)
                .webViewLinkPreviews(.enabled)
                .webViewTextSelection(.enabled)
                .webViewBackForwardNavigationGestures(.enabled)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    if page.isLoading {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .tint(.primary)
                    }
                }
                .navigationTitle(page.title ?? url.host() ?? "Article")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Back", systemImage: "chevron.backward") {
                            if let item = page.backForwardList.backList.last { _ = page.load(item) }
                        }
                        .disabled(page.backForwardList.backList.isEmpty)
                        Button("Forward", systemImage: "chevron.forward") {
                            if let item = page.backForwardList.forwardList.first { _ = page.load(item) }
                        }
                        .disabled(page.backForwardList.forwardList.isEmpty)
                        ShareLink(item: url)
                        Link(destination: url) {
                            Image(systemName: "safari")
                        }
                        .accessibilityLabel("Open in Safari")
                    }
                }
                .task(id: url) { _ = page.load(URLRequest(url: url)) }
        }
    }
}
