import SwiftUI
import WebKit

struct ArticleBrowserView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var page: WebPage
    @State private var showLoadingMark = false

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
                .safeAreaBar(edge: .top, spacing: 0) {
                    BrowserLoadingLine(isShown: showLoadingMark)
                }
                .toolbar {
                    ToolbarItem(placement: .oneFeedLeading) {
                        Button("Close", systemImage: "xmark") { dismiss() }
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
                .task(id: page.isLoading) {
                    guard page.isLoading else {
                        showLoadingMark = false
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(160))
                    guard !Task.isCancelled, page.isLoading else { return }
                    showLoadingMark = true
                }
        }
    }
}

/// A 2-point line in the top safe area. It does not take a toolbar slot, so Back and Share stay put while the page loads.
private struct BrowserLoadingLine: View {
    var isShown: Bool

    var body: some View {
        Rectangle()
            .fill(OneFeedTheme.accent)
            .frame(height: isShown ? 2 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .animation(nil, value: isShown)
            .allowsHitTesting(false)
            .accessibilityHidden(!isShown)
            .accessibilityLabel("Loading page")
            .accessibilityAddTraits(isShown ? .updatesFrequently : [])
    }
}
