import SwiftUI
import WebKit

enum ReaderDisplayMode: String, CaseIterable, Identifiable {
    case reader
    case website

    var id: Self { self }
    var title: String {
        switch self {
        case .reader: "Reader"
        case .website: "Website"
        }
    }
}

struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(AppPreferenceKey.readerFont) private var fontChoice = ReaderFontChoice.sans.rawValue
    @AppStorage(AppPreferenceKey.readerTextSize) private var textSize = ReaderTextSize.standard.rawValue
    @State private var viewModel: ReaderViewModel
    @State private var mode: ReaderDisplayMode
    @State private var isPresentingBrowser = false
    let onFinish: (ArticleState) -> Void

    init(article: Article, onFinish: @escaping (ArticleState) -> Void) {
        _viewModel = State(initialValue: ReaderViewModel(article: article))
        _mode = State(initialValue: article.readableHTML == nil && article.url != nil ? .website : .reader)
        self.onFinish = onFinish
    }

    var body: some View {
        NavigationStack {
            Group {
                if mode == .website, let url = viewModel.article.url {
                    inAppWebsite(url)
                } else {
                    ReaderWebContent(html: viewModel.documentHTML(
                        fontChoice: ReaderFontChoice(rawValue: fontChoice) ?? .sans,
                        textSize: ReaderTextSize(rawValue: textSize) ?? .standard
                    ))
                    .id(dynamicTypeSize)
                }
            }
            .background(OneFeedTheme.page)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                readerActions
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "chevron.down") { dismiss() }
                        .accessibilityHint("Closes the reader without changing this article")
                }
                ToolbarItem(placement: .principal) {
                    if viewModel.article.url != nil {
                        Picker("View", selection: $mode) {
                            ForEach(ReaderDisplayMode.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 220)
                        .accessibilityLabel("Reading mode")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.article.url != nil {
                        Button("Open browser", systemImage: "safari") {
                            isPresentingBrowser = true
                        }
                        .accessibilityHint("Opens a full in-app browser")
                    }
                }
            }
            .toolbarTitleDisplayMode(.inline)
            .sheet(isPresented: $isPresentingBrowser) {
                if let url = viewModel.article.url {
                    ArticleBrowserView(url: url)
                }
            }
        }
    }

    @ViewBuilder
    private func inAppWebsite(_ url: URL) -> some View {
        WebsiteReaderPane(url: url)
    }

    private var readerActions: some View {
        HStack(spacing: 10) {
            Button { onFinish(.saved) } label: { Label("Save", systemImage: "bookmark") }
                .buttonStyle(DecisionActionStyle())
                .accessibilityHint("Saves this article for later")
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

private struct WebsiteReaderPane: View {
    let url: URL
    @State private var page: WebPage

    init(url: URL) {
        self.url = url
        var configuration = WebPage.Configuration()
        configuration.loadsSubresources = true
        configuration.defaultNavigationPreferences.allowsContentJavaScript = true
        _page = State(initialValue: WebPage(configuration: configuration))
    }

    var body: some View {
        WebView(page)
            .webViewLinkPreviews(.enabled)
            .webViewTextSelection(.enabled)
            .webViewBackForwardNavigationGestures(.enabled)
            .overlay(alignment: .top) {
                if page.isLoading {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
            }
            .task(id: url) { _ = page.load(URLRequest(url: url)) }
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
