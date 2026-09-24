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
        configuration.websiteDataStore = .nonPersistent()
        _page = State(initialValue: WebPage(configuration: configuration))
    }

    var body: some View {
        NavigationStack {
            WebView(page)
                .webViewLinkPreviews(.enabled)
                .webViewTextSelection(.enabled)
                .webViewBackForwardNavigationGestures(.enabled)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(page.title ?? url.host() ?? "Article")
                .oneFeedInlineTitle()
                .toolbar {
                    ToolbarItem(placement: .oneFeedLeading) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                    }
                    if page.isLoading {
                        ToolbarItem(placement: .oneFeedTrailing) {
                            OneFeedMarkPulse(isActive: true, size: 18)
                                .frame(minWidth: 44, minHeight: 44)
                                .accessibilityLabel("Loading page")
                        }
                    }
                    ToolbarItemGroup(placement: .oneFeedTrailing) {
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
