import SwiftUI
import WebKit
import SwiftData

enum ReaderDisplayMode: String, CaseIterable, Identifiable {
    case reader
    case website

    var id: Self { self }

    func title(for contentKind: String) -> String {
        switch self {
        case .reader: contentKind == "youtube" ? "Summary" : "Reader"
        case .website:
            if contentKind == "pdf" { "PDF" }
            else if contentKind == "youtube" { "Video" }
            else { "Website" }
        }
    }
}

struct ReaderView: View {
    private enum GeminiKeyFollowUp {
        case summarize
        case ask
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.legibilityWeight) private var legibilityWeight
    @AppStorage(AppPreferenceKey.readerFont) private var fontChoice = ReaderFontChoice.serif.rawValue
    @AppStorage(AppPreferenceKey.readerTextSize) private var textSize = ReaderTextSize.standard.rawValue
    @AppStorage(AppPreferenceKey.readerFocusMode) private var focusMode = ReaderFocusMode.smart.rawValue
    @AppStorage(AppPreferenceKey.readerFocusIntensity) private var focusIntensity = ReaderFocus.defaultIntensity
    @State private var viewModel: ReaderViewModel
    @State private var mode: ReaderDisplayMode
    @State private var isPresentingBrowser = false
    @State private var showingFocusSheet = false
    @State private var showingTakeaway = false
    @State private var takeawayError: String?
    @State private var filingError: String?
    @State private var pendingReadFinish = false
    @State private var decision: ArticleState?
    @State private var showingSummaryPrompt = false
    @State private var didOfferSummary = false
    @State private var showingAPIKeySheet = false
    @State private var showingVideoChat = false
    @State private var geminiKey = ""
    @State private var geminiKeyFollowUp: GeminiKeyFollowUp?
    @State private var openVideoChatAfterKey = false
    /// Persists the decision and dismisses when it returns true. False leaves the reader open.
    let onFinish: (ArticleState) -> Bool
    var onClose: (() -> Void)?
    var onPutInQueue: (() -> Void)?

    init(
        article: Article,
        onFinish: @escaping (ArticleState) -> Bool,
        onClose: (() -> Void)? = nil,
        onPutInQueue: (() -> Void)? = nil
    ) {
        _viewModel = State(initialValue: ReaderViewModel(article: article))
        _mode = State(initialValue: Self.initialMode(for: article))
        self.onFinish = onFinish
        self.onClose = onClose
        self.onPutInQueue = onPutInQueue
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
                ZStack {
                    if let decision {
                        OneFeedDecisionCurtain(state: decision)
                            .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : OneFeedMotion.decision, value: decision)
            }
            .onChange(of: viewModel.hasAISummary) { _, ready in
                if ready, article.contentKind == "youtube" {
                    mode = .reader
                }
            }
            #if os(macOS)
            .toolbar(.hidden)
            #endif
            .task(id: article.id) {
                await viewModel.enrichReadableHTML()
                guard !Task.isCancelled, !didOfferSummary, viewModel.shouldOfferYouTubeSummary else { return }
                didOfferSummary = true
                showingSummaryPrompt = true
            }
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .oneFeedLeading) {
                    Button("Close", systemImage: "xmark") { closeReader() }
                        .disabled(decision != nil)
                        .accessibilityHint("Closes the reader without changing this article")
                }
                ToolbarItem(placement: .principal) {
                    if showsModePicker {
                        modePicker
                    }
                }
                ToolbarItem(placement: .oneFeedTrailing) {
                    if showsReadingOptions {
                        readingOptionsControl
                    } else if viewModel.isExtracting || viewModel.isSummarizing {
                        readerActivityMark
                    }
                }
            }
            .oneFeedInlineTitle()
            #endif
            .sheet(isPresented: $isPresentingBrowser) {
                if let url = viewModel.article.url {
                    ArticleBrowserView(url: url)
                        .oneFeedMacSheetCanvas()
                }
            }
            .confirmationDialog("Summarize this video?", isPresented: $showingSummaryPrompt, titleVisibility: .visible) {
                Button("Summarize") {
                    summarizeVideoIfReady()
                }
                Button("Not now", role: .cancel) {
                    viewModel.declineYouTubeSummary()
                }
            } message: {
                Text("Gemini writes a short article from the video, in this same reader. This uses your Google AI Studio key.")
            }
            .alert("Couldn’t summarize", isPresented: Binding(
                get: { viewModel.summaryError != nil && !viewModel.isSummarizing },
                set: { if !$0 { viewModel.summaryError = nil } }
            )) {
                Button("Try again") { viewModel.beginSummary() }
                Button("OK", role: .cancel) { viewModel.summaryError = nil }
            } message: {
                Text(viewModel.summaryError ?? "")
            }
            .alert("Couldn’t keep this article", isPresented: Binding(
                get: { viewModel.bodyError != nil },
                set: { if !$0 { viewModel.bodyError = nil } }
            )) {
                Button("OK", role: .cancel) { viewModel.bodyError = nil }
            } message: {
                Text(viewModel.bodyError ?? "")
            }
            .alert("Couldn’t file that", isPresented: Binding(
                get: { filingError != nil },
                set: { if !$0 { filingError = nil } }
            )) {
                Button("OK", role: .cancel) { filingError = nil }
            } message: {
                Text(filingError ?? "")
            }
            .sheet(isPresented: $showingFocusSheet) {
                ReaderFocusSheet(mode: $focusMode, intensity: $focusIntensity)
            }
            .sheet(isPresented: $showingTakeaway, onDismiss: {
                if pendingReadFinish {
                    pendingReadFinish = false
                    finish(.read)
                }
            }) {
                ReadingTakeawaySheet(article: article) { message in
                    takeawayError = message
                }
            }
            .alert("Couldn’t save that note", isPresented: Binding(
                get: { takeawayError != nil },
                set: { if !$0 { takeawayError = nil } }
            )) {
                Button("OK", role: .cancel) { takeawayError = nil }
            } message: {
                Text(takeawayError ?? "")
            }
            .sheet(isPresented: $showingAPIKeySheet, onDismiss: {
                guard openVideoChatAfterKey else { return }
                openVideoChatAfterKey = false
                showingVideoChat = true
            }) {
                GeminiAPIKeyForm(key: $geminiKey) {
                    GeminiAPIKeyStore.save(geminiKey)
                    showingAPIKeySheet = false
                    let followUp = geminiKeyFollowUp
                    geminiKeyFollowUp = nil
                    guard GeminiAPIKeyStore.load() != nil else { return }
                    switch followUp {
                    case .summarize:
                        viewModel.beginSummary()
                    case .ask:
                        openVideoChatAfterKey = true
                    case nil:
                        break
                    }
                }
                .onAppear { geminiKey = GeminiAPIKeyStore.load() ?? "" }
            }
            .sheet(isPresented: $showingVideoChat) {
                VideoChatSheet(viewModel: viewModel)
                    .alert("Couldn’t ask", isPresented: Binding(
                        get: { viewModel.askError != nil && !viewModel.isAskingVideo },
                        set: { if !$0 { viewModel.askError = nil } }
                    )) {
                        Button("OK", role: .cancel) { viewModel.askError = nil }
                    } message: {
                        Text(viewModel.askError ?? "")
                    }
            }
        }
    }

    private var article: Article { viewModel.article }

    private var queueIsFilled: Bool {
        decision == .saved || article.state == .saved
    }

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
                beginFinishRead()
            } label: {
                Label("Done", systemImage: "checkmark")
            }
            .buttonStyle(PrimaryActionStyle())
            .disabled(decision != nil)
            .accessibilityLabel("Done")
            .accessibilityHint("Marks this article done")

            readerSecondaryAction(
                queueIsFilled ? "In Queue" : "Queue",
                systemImage: queueIsFilled ? "square.stack.fill" : "square.stack",
                hint: queueIsFilled ? "Already in Queue" : "Adds this to Queue",
                disabled: article.state == .saved
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
                systemImage: queueIsFilled ? "square.stack.fill" : "square.stack",
                hint: queueIsFilled ? "Already in Queue" : "Adds this to Queue",
                accessibilityLabel: queueIsFilled ? "In Queue" : "Queue",
                disabled: article.state == .saved
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
                beginFinishRead()
            }
            ShareLink(item: shareURL ?? URL(fileURLWithPath: "/")) {
                ReaderBarItemLabel(
                    title: "Share",
                    systemImage: "square.and.arrow.up",
                    spokenLabel: "Share",
                    spokenHint: "Shares this article"
                )
            }
            .buttonStyle(ReaderBarPressStyle())
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
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, minHeight: 44)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(DecisionActionStyle())
        .disabled(decision != nil || disabled)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }

    private func readerBarItem(
        _ title: String,
        systemImage: String,
        hint: String,
        emphasized: Bool = false,
        accessibilityLabel: String? = nil,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ReaderBarItemLabel(
                title: title,
                systemImage: systemImage,
                emphasized: emphasized,
                spokenLabel: accessibilityLabel ?? title,
                spokenHint: hint
            )
        }
        .buttonStyle(ReaderBarPressStyle())
        .disabled(decision != nil || disabled)
        .frame(maxWidth: .infinity)
    }
    #endif

    private func finishNotInterested() {
        ReadingUndo.begin(article, in: modelContext)
        do {
            try NotInterestedLog.record(article, in: modelContext)
        } catch {
            filingError = UserFacingFailure.message(for: error, fallback: "Couldn’t file that as not interested.")
            return
        }
        finish(.skipped)
    }

    private func beginFinishRead() {
        guard decision == nil, !showingTakeaway else { return }
        pendingReadFinish = true
        showingTakeaway = true
    }

    private func finish(_ state: ArticleState) {
        guard decision == nil else { return }
        if state == .saved, article.state == .saved { return }
        decision = state
        Task { @MainActor in
            await OneFeedMotion.holdBeforeDismiss(reduceMotion: reduceMotion, for: state)
            guard onFinish(state) else {
                decision = nil
                return
            }
            OneFeedMotion.acknowledge(state)
        }
    }

    @ViewBuilder
    private var modePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Menu {
                Picker("View", selection: $mode) {
                    ForEach(ReaderDisplayMode.allCases) { option in
                        Text(option.title(for: article.contentKind)).tag(option)
                    }
                }
            } label: {
                Text(mode.title(for: article.contentKind))
                    .font(.body.weight(.medium))
            }
            .accessibilityLabel("Reading mode, \(mode.title(for: article.contentKind))")
        } else {
            Picker("View", selection: $mode) {
                ForEach(ReaderDisplayMode.allCases) { option in
                    Text(option.title(for: article.contentKind)).tag(option)
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
            Divider()
            if onPutInQueue != nil {
                Button("Put in Queue", systemImage: "square.stack") {
                    onPutInQueue?()
                }
            }
            Button("Not interested", systemImage: "hand.thumbsdown") {
                finishNotInterested()
            }
            .disabled(decision != nil)
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
                    summarizeVideoIfReady()
                }
                .disabled(viewModel.isSummarizing)
                Button("Ask about this video", systemImage: "text.bubble") {
                    askAboutVideoIfReady()
                }
            }
        } label: {
            Image(systemName: "textformat.size")
                #if os(macOS)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                #endif
        }
        .accessibilityLabel("Reading options")
        .accessibilityValue(ReaderFocusMode(rawValue: focusMode)?.label ?? "Smart")
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
    }

    /// The loading mark covers this control instead of pushing it aside.
    private var readingOptionsControl: some View {
        readingOptionsMenu
            .frame(minWidth: 44, minHeight: 44)
            .overlay {
                if viewModel.isExtracting || viewModel.isSummarizing {
                    readerActivityMark
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel(viewModel.isSummarizing ? "Summarizing" : viewModel.isExtracting ? "Loading" : "Reading options")
    }

    private var readerActivityMark: some View {
        OneFeedMarkPulse(isActive: true, size: 18)
            .frame(minWidth: 44, minHeight: 44)
            .allowsHitTesting(false)
            .accessibilityLabel(viewModel.isSummarizing ? "Summarizing" : "Loading")
    }

    #if os(macOS)
    private var readerTopBar: some View {
        HStack(spacing: 12) {
            Button {
                closeReader()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(decision != nil)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
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
                readingOptionsControl
            } else if viewModel.isExtracting || viewModel.isSummarizing {
                readerActivityMark
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
                readerBarButton(
                    "Queue",
                    systemImage: queueIsFilled ? "square.stack.fill" : "square.stack",
                    help: queueIsFilled ? "Already in Queue" : "Add this to Queue",
                    accessibilityLabel: queueIsFilled ? "In Queue" : "Queue"
                ) {
                    finish(.saved)
                }
                .disabled(decision != nil || article.state == .saved)
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
                beginFinishRead()
            }
            .disabled(decision != nil)
            .frame(minWidth: 88)
            HStack(spacing: 0) {
                ShareLink(item: shareURL ?? URL(fileURLWithPath: "/")) {
                    ReaderBarGlyph(
                        title: "Share",
                        systemImage: "square.and.arrow.up",
                        spokenLabel: "Share",
                        spokenHint: "Shares this article"
                    )
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
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ReaderBarGlyph(
                title: title,
                systemImage: systemImage,
                emphasized: emphasized,
                spokenLabel: accessibilityLabel ?? title,
                spokenHint: help
            )
        }
        .buttonStyle(ReaderBarPressStyle())
        .help(help)
    }
    #endif

    @ViewBuilder
    private var articleCanvas: some View {
        if article.contentKind == "pdf", mode == .website {
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
                    textSize: ReaderTextSize(rawValue: textSize) ?? .standard,
                    boldText: legibilityWeight == .bold
                ),
                metaLine: viewModel.readerMetaLine,
                title: article.title,
                articleID: article.id,
                baseURL: viewModel.documentBaseURL
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
        if article.contentKind == "pdf" {
            return ImportedDocumentStore.shared.resolvedFileURL(for: article) != nil
        }
        return !article.isImportedDocument && article.url != nil
    }

    private var showsReadingOptions: Bool {
        if article.contentKind == "pdf" { return mode == .reader }
        return true
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
        if article.contentKind == "pdf" {
            return article.readableHTML == nil ? .website : .reader
        }
        if article.isImportedDocument { return .reader }
        if article.contentKind == "youtube" {
            let summary = article.aiSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return summary.isEmpty ? .website : .reader
        }
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

    private func summarizeVideoIfReady() {
        if GeminiAPIKeyStore.load() == nil {
            geminiKeyFollowUp = .summarize
            showingAPIKeySheet = true
        } else {
            viewModel.beginSummary()
        }
    }

    private func askAboutVideoIfReady() {
        if GeminiAPIKeyStore.load() == nil {
            geminiKeyFollowUp = .ask
            showingAPIKeySheet = true
        } else {
            showingVideoChat = true
        }
    }
}

private struct ReaderBarPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect((reduceMotion || !configuration.isPressed) ? 1 : 0.97)
            .animation(reduceMotion ? nil : OneFeedMotion.press, value: configuration.isPressed)
    }
}

private struct ReaderBarItemLabel: View {
    let title: String
    let systemImage: String
    var emphasized = false
    var spokenLabel: String?
    var spokenHint: String?
    @ScaledMetric(relativeTo: .body) private var iconSize = 32.0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel ?? title)
        .accessibilityHint(spokenHint ?? "")
    }
}

#if os(macOS)
private struct ReaderBarGlyph: View {
    let title: String
    let systemImage: String
    var emphasized = false
    var spokenLabel: String?
    var spokenHint: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.caption2.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel ?? title)
        .accessibilityHint(spokenHint ?? "")
    }
}
#endif

/// Returns when the page stops loading, or after the opening-cover timeout.
/// The first pause is 80ms so a page that is already ready does not apply focus on the same frame.
/// Later pauses are 160ms so a slow page does not wake the reader on every frame.
private func waitForPageSettled(_ page: WebPage) async {
    let clock = ContinuousClock()
    let start = clock.now
    var poll = 0
    while !Task.isCancelled {
        try? await Task.sleep(for: ReaderFocus.pageSettlePause(after: poll))
        if !page.isLoading { return }
        if clock.now - start > .seconds(8) { return }
        poll += 1
    }
}

private struct WebsiteReaderPane: View {
    let url: URL
    let title: String
    var isVideo = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: WebPage
    @State private var hasCommitted = ReaderWebWarmup.skipsOpeningCover
    @State private var allowCover = false

    init(url: URL, title: String, isVideo: Bool = false) {
        self.url = url
        self.title = title
        self.isVideo = isVideo
        var configuration = WebPage.Configuration()
        configuration.loadsSubresources = true
        configuration.defaultNavigationPreferences.allowsContentJavaScript = true
        _page = State(initialValue: WebPage(configuration: configuration))
    }

    private var showCover: Bool { !hasCommitted && allowCover }

    var body: some View {
        WebView(page)
            .webViewLinkPreviews(.enabled)
            .webViewTextSelection(.enabled)
            .webViewBackForwardNavigationGestures(.enabled)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                ZStack {
                    if showCover {
                        OneFeedLoadingCover(
                            title: title,
                            status: isVideo ? "Opening the video" : "Opening the site"
                        )
                        .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : OneFeedMotion.overlay, value: showCover)
            }
            .onChange(of: page.isLoading) { _, loading in
                if !loading { hasCommitted = true }
            }
            .task(id: url) {
                allowCover = false
                async let cover: Void = revealCoverIfStillWaiting()
                _ = page.load(URLRequest(url: url))
                await waitForPageSettled(page)
                hasCommitted = true
                allowCover = false
                _ = await cover
            }
    }

    private func revealCoverIfStillWaiting() async {
        try? await Task.sleep(for: .milliseconds(160))
        guard !Task.isCancelled, !hasCommitted else { return }
        allowCover = true
    }
}

private struct ReaderWebContent: View {
    let html: String
    let metaLine: String
    let title: String
    let articleID: UUID
    var baseURL: URL = ReaderWebWarmup.blankURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppPreferenceKey.readerFocusMode) private var focusMode = ReaderFocusMode.smart.rawValue
    @AppStorage(AppPreferenceKey.readerFocusIntensity) private var focusIntensity = ReaderFocus.defaultIntensity
    @AppStorage(AppPreferenceKey.readerFocusZoneY) private var focusZoneY = ReaderFocus.defaultZoneY
    @State private var page = ReaderWebWarmup.makeReaderPage()
    @State private var hasCommitted = ReaderWebWarmup.skipsOpeningCover
    @State private var allowCover = false
    @State private var didRestoreTrail = false
    @State private var lastPersistedTrail: ReadingTrail?
    /// The page already applied a zone the reader dragged. Skip the echo that would reconfigure focus mid-scroll.
    @State private var ignoreNextZoneApply = false
    /// Latest focus change wins. A drag does not stack a configure for every step.
    @State private var focusApply: Task<Void, Never>?
    /// One byline update at a time. A later length replaces one already waiting.
    @State private var metaTask: Task<Void, Never>?
    @State private var pendingMeta: String?
    /// One reading-position snapshot at a time. A second request runs after the first.
    @State private var trailTask: Task<Void, Never>?
    @State private var trailAgain = false
    /// True while the current page is being saved before a new page replaces it.
    @State private var replacingPage = false

    private var showCover: Bool { !hasCommitted && allowCover }
    private var resolvedMode: ReaderFocusMode {
        ReaderFocusMode(rawValue: focusMode) ?? .smart
    }

    var body: some View {
        WebView(page)
            .webViewLinkPreviews(.enabled)
            .webViewTextSelection(.enabled)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                ZStack {
                    if showCover {
                        OneFeedLoadingCover(title: title, status: "Laying the page")
                            .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : OneFeedMotion.overlay, value: showCover)
            }
            .onChange(of: page.isLoading) { _, loading in
                if !loading { hasCommitted = true }
            }
            .onChange(of: focusMode) { _, _ in
                scheduleFocusApply()
            }
            .onChange(of: focusIntensity) { _, _ in
                scheduleFocusApply()
            }
            .onChange(of: focusZoneY) { _, _ in
                if ignoreNextZoneApply {
                    ignoreNextZoneApply = false
                    return
                }
                scheduleFocusApply()
            }
            .onChange(of: metaLine) { _, line in
                scheduleMeta(line)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    scheduleTrailPersist()
                }
            }
            .onDisappear {
                focusApply?.cancel()
                metaTask?.cancel()
                pendingMeta = nil
                scheduleTrailPersist()
            }
            .task(id: html) {
                if hasCommitted, didRestoreTrail {
                    await persistTrailBeforeReplace()
                }
                didRestoreTrail = false
                lastPersistedTrail = nil
                ignoreNextZoneApply = false
                allowCover = false
                async let cover: Void = revealCoverIfStillWaiting()
                page.load(html: html, baseURL: baseURL)
                await waitForPageSettled(page)
                hasCommitted = true
                allowCover = false
                _ = await cover
                await applyFocus(restore: !didRestoreTrail)
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: ReaderFocus.trailSnapshotInterval)
                    if Task.isCancelled { return }
                    scheduleTrailPersist()
                }
            }
    }

    private func revealCoverIfStillWaiting() async {
        try? await Task.sleep(for: .milliseconds(160))
        guard !Task.isCancelled, !hasCommitted else { return }
        allowCover = true
    }

    private func scheduleMeta(_ line: String) {
        pendingMeta = line
        guard metaTask == nil else { return }
        metaTask = Task {
            while !Task.isCancelled, let line = pendingMeta {
                pendingMeta = nil
                await updateMeta(line)
            }
            metaTask = nil
            if let line = pendingMeta, !Task.isCancelled {
                scheduleMeta(line)
            }
        }
    }

    /// Saves the place, then lets the caller load the next page.
    /// A snapshot already running finishes first. One later snapshot runs after it.
    private func persistTrailBeforeReplace() async {
        replacingPage = true
        defer {
            replacingPage = false
            trailAgain = false
        }
        if trailTask == nil {
            await persistTrail()
            return
        }
        trailAgain = true
        while let running = trailTask {
            await running.value
        }
        guard trailAgain else { return }
        trailAgain = false
        await persistTrail()
    }

    private func scheduleTrailPersist() {
        if replacingPage {
            trailAgain = true
            return
        }
        if trailTask != nil {
            trailAgain = true
            return
        }
        trailTask = Task {
            await persistTrail()
            trailTask = nil
            if trailAgain, !Task.isCancelled {
                trailAgain = false
                scheduleTrailPersist()
            }
        }
    }

    @MainActor
    private func updateMeta(_ line: String) async {
        _ = try? await page.callJavaScript(
            "var meta = document.querySelector('.meta'); if (meta) { meta.textContent = text; }",
            arguments: ["text": line]
        )
    }

    private func scheduleFocusApply() {
        focusApply?.cancel()
        focusApply = Task {
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            await applyFocus(restore: false)
        }
    }

    @MainActor
    private func applyFocus(restore: Bool) async {
        guard !Task.isCancelled else { return }
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
        if let last = lastPersistedTrail,
           last.blockIndex == trail.blockIndex,
           last.anchor == trail.anchor,
           abs(last.scrollRatio - trail.scrollRatio) < 0.002,
           abs(last.zoneY - trail.zoneY) < 0.002 {
            return
        }
        lastPersistedTrail = trail
        ReadingTrailStore.save(trail)
        if abs(trail.zoneY - focusZoneY) > 0.002 {
            ignoreNextZoneApply = true
            focusZoneY = trail.zoneY
        }
    }
}
