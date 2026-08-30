import SwiftUI
import WebKit

struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(AppPreferenceKey.readerFont) private var fontChoice = ReaderFontChoice.sans.rawValue
    @AppStorage(AppPreferenceKey.readerTextSize) private var textSize = ReaderTextSize.standard.rawValue
    @State private var viewModel: ReaderViewModel
    let onFinish: (ArticleState) -> Void

    init(article: Article, onFinish: @escaping (ArticleState) -> Void) {
        _viewModel = State(initialValue: ReaderViewModel(article: article))
        self.onFinish = onFinish
    }

    var body: some View {
        NavigationStack {
            ReaderWebContent(html: viewModel.documentHTML(
                fontChoice: ReaderFontChoice(rawValue: fontChoice) ?? .sans,
                textSize: ReaderTextSize(rawValue: textSize) ?? .standard
            ))
            .id(dynamicTypeSize)
            .background(OneFeedTheme.page)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                readerActions
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "chevron.down") { dismiss() }
                        .accessibilityHint("Closes the reader without changing this article")
                }
            }
            .toolbarTitleDisplayMode(.inline)
        }
    }

    private var readerActions: some View {
        HStack(spacing: 10) {
            Button { onFinish(.saved) } label: { Label("Save", systemImage: "bookmark") }
                .buttonStyle(DecisionActionStyle())
                .accessibilityHint("Saves this article for later")
            if let url = viewModel.article.url {
                Link(destination: url) { Label("Original", systemImage: "arrow.up.right") }
                    .buttonStyle(DecisionActionStyle())
                    .accessibilityHint("Opens the original article")
            }
            Button { onFinish(.read) } label: { Label("Done", systemImage: "checkmark") }
                .buttonStyle(DecisionActionStyle())
                .accessibilityHint("Marks this article done")
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, OneFeedTheme.pagePadding)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct ReaderWebContent: View {
    let html: String
    @State private var page: WebPage

    init(html: String) {
        self.html = html
        var configuration = WebPage.Configuration()
        configuration.loadsSubresources = true
        configuration.defaultNavigationPreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        _page = State(initialValue: WebPage(configuration: configuration))
    }

    var body: some View {
        WebView(page)
            .webViewLinkPreviews(.enabled)
            .webViewTextSelection(.enabled)
            .task(id: html) { page.load(html: html, baseURL: URL(string: "about:blank")!) }
    }
}
