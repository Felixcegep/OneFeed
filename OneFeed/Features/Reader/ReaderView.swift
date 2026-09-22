import SwiftUI
import WebKit
import SwiftData

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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppPreferenceKey.readerFont) private var fontChoice = ReaderFontChoice.serif.rawValue
    @AppStorage(AppPreferenceKey.readerTextSize) private var textSize = ReaderTextSize.standard.rawValue
    @AppStorage(AppPreferenceKey.readerFocusMode) private var focusMode = ReaderFocusMode.smart.rawValue
    @AppStorage(AppPreferenceKey.readerFocusIntensity) private var focusIntensity = ReaderFocus.defaultIntensity
    @State private var viewModel: ReaderViewModel
    @State private var mode: ReaderDisplayMode
    @State private var isPresentingBrowser = false
    @State private var showingFocusSheet = false
    @State private var savePulse = 0
    @State private var donePulse = 0
    @State private var skipPulse = 0
    @State private var decision: ArticleState?
    @State private var showingSummaryPrompt = false
    @State private var showingAPIKeySheet = false
    @State private var geminiKey = ""
    let onFinish: (ArticleState) -> Void
    var onClose: (() -> Void)?

    init(article: Article, onFinish: @escaping (ArticleState) -> Void, onClose: (() -> Void)? = nil) {
        _viewModel = State(initialValue: ReaderViewModel(article: article))
        _mode = State(initialValue: Self.initialMode(for: article))
        self.onFinish = onFinish
        self.onClose = onClose
    }

    private func closeReader() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
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
            #if os(iOS)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                readerActionBar
            }
            #endif
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
                    if showsModePicker {
                        modePicker
                    }
                }
                ToolbarItem(placement: .oneFeedTrailing) {
                    HStack(spacing: 10) {
                        if viewModel.isExtracting {
                            OneFeedMarkPulse(isActive: true, size: 18)
                        }
                        if showsReadingOptions {
                            readingOptionsMenu
                        }
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
            .sheet(isPresented: $showingFocusSheet) {
                ReaderFocusSheet(mode: $focusMode, intensity: $focusIntensity)
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

    #if os(iOS)
    /// Standard sizes keep five equal slots. Accessibility sizes stack a full-width
    /// Done control above the remaining actions so captions never clip or scroll away.
    private var readerActionBar: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                readerAccessibilityActions
            } else {
                readerActionItems
            }
        }
        .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 16 : 8)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background {
            OneFeedTheme.paper
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(OneFeedTheme.sand)
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityElement(children: .contain)
    }

    private var readerAccessibilityActions: some View {
        VStack(spacing: 8) {
            Button {
                finish(.read)
            } label: {
                Label("Done", systemImage: "checkmark")
            }
            .buttonStyle(PrimaryActionStyle())
            .disabled(decision != nil)
            .accessibilityLabel("Done")
            .accessibilityHint("Marks this article done")

            readerSecondaryAction(
                "Queue",
                systemImage: decision == .saved ? "square.stack.fill" : "square.stack",
                hint: "Adds this to Queue"
            ) {
                finish(.saved)
            }
            readerSecondaryAction("Skip", systemImage: "forward", hint: "Skip this article") {
                finish(.skipped)
            }
            readerSecondaryAction(
                "Not interested",
                systemImage: "hand.thumbsdown",
                hint: "Sets this article aside and skips it"
            ) {
                finishNotInterested()
            }
        }
    }

    private var readerActionItems: some View {
        HStack(spacing: 0) {
            readerBarItem(
                "Queue",
                systemImage: decision == .saved ? "square.stack.fill" : "square.stack",
                hint: "Adds this to Queue"
            ) {
                finish(.saved)
            }
            readerBarItem("Skip", systemImage: "forward", hint: "Skip this article. Hold for Not interested.") {
                finish(.skipped)
            }
            .contextMenu {
                Button("Not interested", systemImage: "hand.thumbsdown") {
                    finishNotInterested()
                }
            }
            readerBarItem("Done", systemImage: "checkmark", hint: "Marks this article done", emphasized: true) {
                finish(.read)
            }
            ShareLink(item: shareURL ?? URL(fileURLWithPath: "/")) {
                ReaderBarItemLabel(title: "Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .disabled(shareURL == nil || decision != nil)
            .accessibilityLabel("Share")
            .frame(maxWidth: .infinity)
            readerBarItem("Browser", systemImage: "safari", hint: "Opens the original page") {
                isPresentingBrowser = true
            }
            .disabled(!canOpenBrowser)
        }
    }

    private func readerSecondaryAction(
        _ title: String,
        systemImage: String,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, minHeight: 44)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(DecisionActionStyle())
        .disabled(decision != nil)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }

    private func readerBarItem(
        _ title: String,
        systemImage: String,
        hint: String,
        emphasized: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ReaderBarItemLabel(title: title, systemImage: systemImage, emphasized: emphasized)
        }
        .buttonStyle(.plain)
        .disabled(decision != nil)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .frame(maxWidth: .infinity)
    }
    #endif

    private func finishNotInterested() {
        NotInterestedLog.record(article, in: modelContext)
        finish(.skipped)
    }

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

    @ViewBuilder
    private var modePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Menu {
                Picker("View", selection: $mode) {
                    ForEach(ReaderDisplayMode.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } label: {
                Text(mode.title)
                    .font(.body.weight(.medium))
            }
            .accessibilityLabel("Reading mode, \(mode.title)")
        } else {
            Picker("View", selection: $mode) {
                ForEach(ReaderDisplayMode.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.tabs)
            .accessibilityLabel("Reading mode")
        }
    }

    private var readingOptionsMenu: some View {
        Menu {
            Button("Focus", systemImage: "text.justify") {
                showingFocusSheet = true
            }
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
            #if os(iOS)
            if dynamicTypeSize.isAccessibilitySize {
                Divider()
                if let url = shareURL {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(decision != nil)
                }
                if canOpenBrowser {
                    Button("Browser", systemImage: "safari") {
                        isPresentingBrowser = true
                    }
                    .disabled(decision != nil)
                }
            }
            #endif
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
                closeReader()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close")
            .accessibilityLabel("Close")
            .accessibilityHint("Closes the reader without changing this article")

            Spacer(minLength: 8)

            if showsModePicker {
                modePicker
                    .frame(maxWidth: 240)
            }

            Spacer(minLength: 8)

            if showsReadingOptions {
                readingOptionsMenu
                    .menuStyle(.borderlessButton)
                    .frame(width: 28, height: 28)
            }

            if viewModel.isExtracting {
                OneFeedMarkPulse(isActive: true, size: 18)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            OneFeedTheme.paper
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(OneFeedTheme.sand)
                        .frame(height: 1)
                }
        }
    }

    private var readerBottomBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                readerBarButton("Queue", systemImage: "square.stack", help: "Add this to Queue") {
                    finish(.saved)
                }
                .disabled(decision != nil)
                readerBarButton("Skip", systemImage: "forward", help: "Skip this article. Hold for Not interested.") {
                    finish(.skipped)
                }
                .disabled(decision != nil)
                .contextMenu {
                    Button("Not interested", systemImage: "hand.thumbsdown") {
                        finishNotInterested()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            readerBarButton("Done", systemImage: "checkmark", help: "Mark this article done", emphasized: true) {
                finish(.read)
            }
            .disabled(decision != nil)
            .frame(width: 88)
            HStack(spacing: 0) {
                ShareLink(item: shareURL ?? URL(fileURLWithPath: "/")) {
                    ReaderBarGlyph(title: "Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .disabled(shareURL == nil)
                .help("Share")
                .accessibilityLabel("Share")
                readerBarButton("Browser", systemImage: "safari", help: "Open in browser") {
                    isPresentingBrowser = true
                }
                .disabled(!canOpenBrowser)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            OneFeedTheme.paper
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(OneFeedTheme.sand)
                        .frame(height: 1)
                }
        }
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
        if article.contentKind == "pdf" {
            if let url = ImportedDocumentStore.shared.resolvedFileURL(for: article) {
                PDFReaderPane(url: url)
            } else {
                missingImportedFile
            }
        } else if mode == .website, let url = playbackURL {
            inAppWebsite(url)
        } else {
            ReaderWebContent(
                html: viewModel.documentHTML(
                    fontChoice: ReaderFontChoice(rawValue: fontChoice) ?? .serif,
                    textSize: ReaderTextSize(rawValue: textSize) ?? .standard
                ),
                title: article.title,
                articleID: article.id,
                baseURL: viewModel.documentBaseURL,
                showingFocusSheet: $showingFocusSheet
            )
        }
    }

    private var missingImportedFile: some View {
        VStack(spacing: 12) {
            Text("This file is no longer on this device.")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(OneFeedTheme.ink)
                .multilineTextAlignment(.center)
            Text("Import the PDF or EPUB again to keep reading.")
                .font(.body)
                .foregroundStyle(OneFeedTheme.graphite)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OneFeedTheme.paper)
    }

    private var showsModePicker: Bool {
        !article.isImportedDocument && article.url != nil
    }

    private var showsReadingOptions: Bool {
        article.contentKind != "pdf"
    }

    private var shareURL: URL? {
        if let file = ImportedDocumentStore.shared.resolvedFileURL(for: article) {
            return file
        }
        let scheme = article.url?.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        return article.url
    }

    private var canOpenBrowser: Bool {
        guard !article.isImportedDocument else { return false }
        let scheme = article.url?.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    private static func initialMode(for article: Article) -> ReaderDisplayMode {
        if article.isImportedDocument { return .reader }
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
        WebsiteReaderPane(url: url, title: article.title, isVideo: article.contentKind == "youtube")
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
                    .font(.system(.body, design: .serif))
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

private struct ReaderBarItemLabel: View {
    let title: String
    let systemImage: String
    var emphasized = false
    @ScaledMetric(relativeTo: .body) private var iconSize = 32.0

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(emphasized ? OneFeedTheme.plaster : OneFeedTheme.ink)
                .background {
                    if emphasized {
                        Circle().fill(OneFeedTheme.ink)
                    }
                }
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(OneFeedTheme.ink)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
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
    let title: String
    var isVideo = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: WebPage
    @State private var hasCommitted = ReaderWebWarmup.skipsOpeningCover

    init(url: URL, title: String, isVideo: Bool = false) {
        self.url = url
        self.title = title
        self.isVideo = isVideo
        var configuration = WebPage.Configuration()
        configuration.loadsSubresources = true
        configuration.defaultNavigationPreferences.allowsContentJavaScript = true
        _page = State(initialValue: WebPage(configuration: configuration))
    }

    private var showCover: Bool { !hasCommitted }

    var body: some View {
        WebView(page)
            .webViewLinkPreviews(.enabled)
            .webViewTextSelection(.enabled)
            .webViewBackForwardNavigationGestures(.enabled)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if showCover {
                    OneFeedLoadingCover(
                        title: title,
                        status: isVideo ? "Opening the video" : "Opening the site"
                    )
                }
            }
            .animation(reduceMotion ? nil : OneFeedMotion.overlay, value: showCover)
            .onChange(of: page.isLoading) { _, loading in
                if !loading { hasCommitted = true }
            }
            .task(id: url) {
                _ = page.load(URLRequest(url: url))
                try? await Task.sleep(for: ReaderWebWarmup.openingCoverTimeout)
                hasCommitted = true
            }
    }
}

private struct ReaderWebContent: View {
    let html: String
    let title: String
    let articleID: UUID
    var baseURL: URL = ReaderWebWarmup.blankURL
    @Binding var showingFocusSheet: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppPreferenceKey.readerFocusMode) private var focusMode = ReaderFocusMode.smart.rawValue
    @AppStorage(AppPreferenceKey.readerFocusIntensity) private var focusIntensity = ReaderFocus.defaultIntensity
    @AppStorage(AppPreferenceKey.readerFocusZoneY) private var focusZoneY = ReaderFocus.defaultZoneY
    @State private var page = ReaderWebWarmup.makeReaderPage()
    @State private var hasCommitted = ReaderWebWarmup.skipsOpeningCover
    @State private var didRestoreTrail = false

    private var showCover: Bool { !hasCommitted }
    private var resolvedMode: ReaderFocusMode {
        ReaderFocusMode(rawValue: focusMode) ?? .smart
    }

    var body: some View {
        WebView(page)
            .webViewLinkPreviews(.enabled)
            .webViewTextSelection(.enabled)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if showCover {
                    OneFeedLoadingCover(title: title, status: "Laying the page")
                }
            }
            .overlay(alignment: .bottom) {
                if !showCover {
                    focusDot
                }
            }
            .animation(reduceMotion ? nil : OneFeedMotion.overlay, value: showCover)
            .onChange(of: page.isLoading) { _, loading in
                if !loading {
                    hasCommitted = true
                    Task { await applyFocus(restore: !didRestoreTrail) }
                }
            }
            .onChange(of: focusMode) { _, _ in
                Task { await applyFocus(restore: false) }
            }
            .onChange(of: focusIntensity) { _, _ in
                Task { await applyFocus(restore: false) }
            }
            .onChange(of: focusZoneY) { _, _ in
                Task { await applyFocus(restore: false) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    Task { await persistTrail() }
                }
            }
            .onDisappear {
                Task { await persistTrail() }
            }
            .task(id: html) {
                didRestoreTrail = false
                page.load(html: html, baseURL: baseURL)
                try? await Task.sleep(for: ReaderWebWarmup.openingCoverTimeout)
                hasCommitted = true
                await applyFocus(restore: !didRestoreTrail)
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2.5))
                    await persistTrail()
                }
            }
    }

    private var focusDot: some View {
        Button {
            showingFocusSheet = true
        } label: {
            Group {
                if resolvedMode == .off {
                    Circle()
                        .strokeBorder(OneFeedTheme.ink.opacity(0.45), lineWidth: 1.5)
                } else {
                    Circle()
                        .fill(OneFeedTheme.ink)
                }
            }
            .frame(width: 7, height: 7)
            .frame(width: 44, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reading focus")
        .accessibilityValue(resolvedMode.label)
        .accessibilityHint("Opens focus options")
        .padding(.bottom, 2)
    }

    @MainActor
    private func applyFocus(restore: Bool) async {
        let trail = restore ? ReadingTrailStore.load(articleID: articleID) : nil
        if restore { didRestoreTrail = true }
        let cfg = ReaderFocus.configuration(
            mode: resolvedMode,
            intensity: focusIntensity,
            zoneY: focusZoneY,
            reduceMotion: reduceMotion,
            trail: trail
        )
        _ = try? await page.callJavaScript(
            "if (window.OneFeedFocus) { window.OneFeedFocus.configure(cfg); }",
            arguments: ["cfg": cfg]
        )
    }

    @MainActor
    private func persistTrail() async {
        let value = try? await page.callJavaScript(
            "return window.OneFeedFocus ? window.OneFeedFocus.snapshot() : null;"
        )
        guard let trail = ReaderFocus.snapshot(from: value, articleID: articleID, fallbackZoneY: focusZoneY) else {
            return
        }
        ReadingTrailStore.save(trail)
        let zone = ReaderFocus.clampZone(trail.zoneY)
        if abs(zone - focusZoneY) > 0.002 {
            focusZoneY = zone
        }
    }
}
