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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppPreferenceKey.readerFont) private var fontChoice = ReaderFontChoice.serif.rawValue
    @AppStorage(AppPreferenceKey.readerTextSize) private var textSize = ReaderTextSize.standard.rawValue
    @State private var viewModel: ReaderViewModel
    @State private var mode: ReaderDisplayMode
    @State private var isPresentingBrowser = false
    @State private var savePulse = 0
    @State private var donePulse = 0
    @State private var skipPulse = 0
    @State private var decision: ArticleState?
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
            VStack(spacing: 0) {
                #if os(macOS)
                readerTopBar
                #endif
                youtubeSummaryBanner
                articleCanvas
                #if os(macOS)
                readerBottomBar
                #endif
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OneFeedTheme.paper)
            .overlay {
                if let decision {
                    OneFeedDecisionCurtain(state: decision)
                }
            }
            .animation(OneFeedMotion.decision, value: decision)
            .animation(OneFeedMotion.overlay, value: viewModel.isExtracting)
            .animation(OneFeedMotion.overlay, value: viewModel.isSummarizing)
            .animation(OneFeedMotion.page, value: mode)
            #if os(macOS)
            .toolbar(.hidden)
            #endif
            .task {
                await viewModel.enrichReadableHTML()
                if viewModel.shouldOfferYouTubeSummary {
                    showingSummaryPrompt = true
                }
            }
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .oneFeedLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .accessibilityHint("Closes the reader without changing this article")
                }
                ToolbarItem(placement: .principal) {
                    if viewModel.article.url != nil {
                        modePicker
                    }
                }
                ToolbarItem(placement: .oneFeedTrailing) {
                    HStack(spacing: 10) {
                        if viewModel.isExtracting {
                            OneFeedMarkPulse(isActive: true, size: 18)
                        }
                        readingOptionsMenu
                    }
                }
                ToolbarItem(placement: .oneFeedBottomBar) {
                    HStack(spacing: 8) {
                        Button("Save", systemImage: decision == .saved ? "star.fill" : "star") {
                            finish(.saved)
                        }
                        .buttonStyle(DecisionActionStyle(expands: false))
                        .disabled(decision != nil)
                        .accessibilityHint("Keeps this in Saved")
                        Button("Skip", systemImage: "forward") {
                            finish(.skipped)
                        }
                        .buttonStyle(DecisionActionStyle(expands: false))
                        .disabled(decision != nil)
                        Spacer(minLength: 8)
                        Button("Done", systemImage: "checkmark") {
                            finish(.read)
                        }
                        .buttonStyle(InkCapsuleStyle())
                        .disabled(decision != nil)
                        .accessibilityHint("Marks this article done")
                        Spacer(minLength: 8)
                        ShareLink(item: article.url ?? URL(fileURLWithPath: "/")) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(OneFeedTheme.ink)
                        }
                        .disabled(article.url == nil)
                        .accessibilityLabel("Share")
                        Button {
                            isPresentingBrowser = true
                        } label: {
                            Image(systemName: "safari")
                                .foregroundStyle(OneFeedTheme.ink)
                        }
                        .disabled(article.url == nil)
                        .accessibilityLabel("Open in browser")
                    }
                }
            }
            .oneFeedInlineTitle()
            #endif
            .sensoryFeedback(.success, trigger: savePulse)
            .sensoryFeedback(.success, trigger: donePulse)
            .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.55), trigger: skipPulse)
            .sheet(isPresented: $isPresentingBrowser) {
                if let url = viewModel.article.url {
                    ArticleBrowserView(url: url)
                        .oneFeedMacSheetCanvas()
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

    private func finish(_ state: ArticleState) {
        guard decision == nil else { return }
        decision = state
        switch state {
        case .saved: savePulse += 1
        case .read: donePulse += 1
        case .skipped: skipPulse += 1
        default: break
        }
        Task { @MainActor in
            await OneFeedMotion.holdBeforeDismiss(reduceMotion: reduceMotion, for: state)
            onFinish(state)
        }
    }

    private var modePicker: some View {
        Picker("View", selection: $mode) {
            ForEach(ReaderDisplayMode.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Reading mode")
    }

    private var readingOptionsMenu: some View {
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

    #if os(macOS)
    private var readerTopBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close")
            .accessibilityLabel("Close")
            .accessibilityHint("Closes the reader without changing this article")

            Spacer(minLength: 8)

            if viewModel.article.url != nil {
                modePicker
                    .frame(maxWidth: 240)
            }

            Spacer(minLength: 8)

            readingOptionsMenu
                .menuStyle(.borderlessButton)
                .frame(width: 28, height: 28)

            if viewModel.isExtracting {
                OneFeedMarkPulse(isActive: true, size: 18)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var readerBottomBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                readerBarButton("Save", systemImage: "star", help: "Keep this in Saved") {
                    finish(.saved)
                }
                .disabled(decision != nil)
                readerBarButton("Skip", systemImage: "forward", help: "Skip this article") {
                    finish(.skipped)
                }
                .disabled(decision != nil)
            }
            .frame(maxWidth: .infinity)
            readerBarButton("Done", systemImage: "checkmark", help: "Mark this article done", emphasized: true) {
                finish(.read)
            }
            .disabled(decision != nil)
            .frame(width: 88)
            HStack(spacing: 0) {
                ShareLink(item: article.url ?? URL(fileURLWithPath: "/")) {
                    ReaderBarGlyph(title: "Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .disabled(article.url == nil)
                .help("Share")
                .accessibilityLabel("Share")
                readerBarButton("Browser", systemImage: "safari", help: "Open in browser") {
                    isPresentingBrowser = true
                }
                .disabled(article.url == nil)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func readerBarButton(
        _ title: String,
        systemImage: String,
        help: String,
        emphasized: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ReaderBarGlyph(title: title, systemImage: systemImage, emphasized: emphasized)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(title)
        .accessibilityHint(help)
    }
    #endif

    @ViewBuilder
    private var articleCanvas: some View {
        if mode == .website, let url = playbackURL {
            inAppWebsite(url)
        } else {
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
            HStack(spacing: 12) {
                OneFeedMarkPulse(isActive: true, size: 18)
                GalleryLabel(text: "Summarizing")
            }
            .padding(.horizontal, OneFeedTheme.pagePadding)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle().fill(OneFeedTheme.sand).frame(height: 1)
            }
            .transition(.opacity)
        } else if let summary = article.aiSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            ScrollView {
                Text(summary)
                    .font(OneFeedTheme.serifBody(16))
                    .foregroundStyle(OneFeedTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
            .padding(.horizontal, OneFeedTheme.pagePadding)
            .padding(.vertical, 16)
            .overlay(alignment: .bottom) {
                Rectangle().fill(OneFeedTheme.sand).frame(height: 1)
            }
            .transition(.opacity)
        }
    }
}

#if os(macOS)
private struct ReaderBarGlyph: View {
    let title: String
    let systemImage: String
    var emphasized = false

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(emphasized ? OneFeedTheme.plaster : OneFeedTheme.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, emphasized ? 8 : 6)
        .background {
            if emphasized {
                Capsule().fill(OneFeedTheme.ink)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(OneFeedTheme.paper)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(OneFeedTheme.sand, lineWidth: 1)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
#endif

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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                if page.isLoading {
                    OneFeedMarkPulse(isActive: true, size: 18)
                        .padding(.top, 8)
                        .transition(.opacity)
                }
            }
            .animation(OneFeedMotion.overlay, value: page.isLoading)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: html) { page.load(html: html, baseURL: baseURL) }
    }
}
