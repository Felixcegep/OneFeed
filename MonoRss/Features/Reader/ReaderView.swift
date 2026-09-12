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
    @AppStorage(AppPreferenceKey.readerFont) private var fontChoice = ReaderFontChoice.serif.rawValue
    @AppStorage(AppPreferenceKey.readerTextSize) private var textSize = ReaderTextSize.standard.rawValue
    @State private var viewModel: ReaderViewModel
    @State private var mode: ReaderDisplayMode
    @State private var isPresentingBrowser = false
    @State private var savePulse = 0
    @State private var showingSummaryPrompt = false
    @State private var showingAPIKeySheet = false
    @State private var geminiKey = ""
    let onFinish: (ArticleState) -> Void

    init(article: Article, onFinish: @escaping (ArticleState) -> Void) {
        _viewModel = State(initialValue: ReaderViewModel(article: article))
        _mode = State(initialValue: Self.initialMode(for: article))
        self.onFinish = onFinish
    }

    var body: some View {
        NavigationStack {
            Group {
                if mode == .website, let url = playbackURL {
                    VStack(spacing: 0) {
                        youtubeSummaryBanner
                        inAppWebsite(url)
                    }
                } else {
                    VStack(spacing: 0) {
                        youtubeSummaryBanner
                        ReaderWebContent(
                            html: viewModel.documentHTML(
                                fontChoice: ReaderFontChoice(rawValue: fontChoice) ?? .serif,
                                textSize: ReaderTextSize(rawValue: textSize) ?? .standard
                            ),
                            baseURL: article.url ?? URL(string: "about:blank")!
                        )
                        .id(dynamicTypeSize)
                    }
                }
            }
            .background(OneFeedTheme.page)
            .overlay(alignment: .top) {
                if viewModel.isExtracting {
                    ProgressView()
                        .padding(.top, 8)
                        .transition(.opacity)
                }
            }
            .animation(OneFeedMotion.overlay, value: viewModel.isExtracting)
            .task {
                await viewModel.enrichReadableHTML()
                if viewModel.shouldOfferYouTubeSummary {
                    showingSummaryPrompt = true
                }
            }
            .toolbar {
                ToolbarItem(placement: .oneFeedLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
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
                ToolbarItem(placement: .oneFeedTrailing) {
                    Menu {
                        Picker("Font", selection: $fontChoice) {
                            ForEach(ReaderFontChoice.allCases) { choice in
                                Text(choice.label).tag(choice.rawValue)
                            }
                        }
                        Picker("Size", selection: $textSize) {
                            ForEach(ReaderTextSize.allCases) { size in
                                Text(size.label).tag(size.rawValue)
                            }
                        }
                        if article.contentKind == "youtube" {
                            Divider()
                            Button("Summarize video", systemImage: "text.quote") {
                                if GeminiAPIKeyStore.load() == nil {
                                    showingAPIKeySheet = true
                                } else {
                                    Task { await viewModel.summarizeYouTube() }
                                }
                            }
                            .disabled(viewModel.isSummarizing)
                        }
                    } label: {
                        Image(systemName: "textformat.size")
                    }
                    .accessibilityLabel("Reading options")
                }
                ToolbarItemGroup(placement: .oneFeedBottomBar) {
                    Button {
                        savePulse += 1
                        onFinish(.saved)
                    } label: {
                        Label("Save", systemImage: "star")
                    }
                    .accessibilityHint("Keeps this in Saved")
                    Button {
                        onFinish(.skipped)
                    } label: {
                        Label("Skip", systemImage: "forward")
                    }
                    Button {
                        onFinish(.read)
                    } label: {
                        Label("Done", systemImage: "checkmark.circle")
                    }
                    .accessibilityHint("Marks this article done")
                    ShareLink(item: article.url ?? URL(fileURLWithPath: "/")) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(article.url == nil)
                    Button("Open browser", systemImage: "safari") {
                        isPresentingBrowser = true
                    }
                    .disabled(article.url == nil)
                    .accessibilityLabel("Open in browser")
                }
            }
            .oneFeedInlineTitle()
            .sensoryFeedback(.success, trigger: savePulse)
            .sheet(isPresented: $isPresentingBrowser) {
                if let url = viewModel.article.url {
                    ArticleBrowserView(url: url)
                }
            }
            .confirmationDialog("Summarize this video?", isPresented: $showingSummaryPrompt, titleVisibility: .visible) {
                Button("Summarize") {
                    if GeminiAPIKeyStore.load() == nil {
                        showingAPIKeySheet = true
                    } else {
                        Task { await viewModel.summarizeYouTube() }
                    }
                }
                Button("Not now", role: .cancel) {
                    viewModel.declineYouTubeSummary()
                }
            } message: {
                Text("Gemini can write a short summary from the YouTube link. This uses your Google AI Studio key.")
            }
            .alert("Couldn’t summarize", isPresented: Binding(
                get: { viewModel.summaryError != nil && !viewModel.isSummarizing },
                set: { if !$0 { viewModel.summaryError = nil } }
            )) {
                Button("Try again") { Task { await viewModel.summarizeYouTube() } }
                Button("OK", role: .cancel) { viewModel.summaryError = nil }
            } message: {
                Text(viewModel.summaryError ?? "")
            }
            .sheet(isPresented: $showingAPIKeySheet) {
                GeminiAPIKeyForm(key: $geminiKey) {
                    GeminiAPIKeyStore.save(geminiKey)
                    showingAPIKeySheet = false
                    if GeminiAPIKeyStore.load() != nil {
                        Task { await viewModel.summarizeYouTube() }
                    }
                }
                .onAppear { geminiKey = GeminiAPIKeyStore.load() ?? "" }
            }
        }
    }

    private var article: Article { viewModel.article }

    private static func initialMode(for article: Article) -> ReaderDisplayMode {
        if article.contentKind == "youtube", article.videoID != nil || article.url != nil { return .website }
        if article.readableHTML == nil, article.url != nil { return .website }
        return .reader
    }

    private var playbackURL: URL? {
        if article.contentKind == "youtube", let videoID = article.videoID {
            return YouTubeProcessor.watchURL(for: videoID) ?? article.url
        }
        return article.url
    }

    @ViewBuilder
    private func inAppWebsite(_ url: URL) -> some View {
        WebsiteReaderPane(url: url)
    }

    @ViewBuilder
    private var youtubeSummaryBanner: some View {
        if article.contentKind != "youtube" {
            EmptyView()
        } else if viewModel.isSummarizing {
            HStack(spacing: 10) {
                ProgressView()
                Text("Summarizing…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, OneFeedTheme.pagePadding)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let summary = article.aiSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            ScrollView {
                Text(summary)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
            .padding(.horizontal, OneFeedTheme.pagePadding)
            .padding(.vertical, 12)
        }
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
                        .padding(.top, 8)
                }
            }
            .task(id: url) { _ = page.load(URLRequest(url: url)) }
    }
}

private struct ReaderWebContent: View {
    let html: String
    let baseURL: URL
    @State private var page: WebPage

    init(html: String, baseURL: URL) {
        self.html = html
        self.baseURL = baseURL
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
            .task(id: html) { page.load(html: html, baseURL: baseURL) }
    }
}
