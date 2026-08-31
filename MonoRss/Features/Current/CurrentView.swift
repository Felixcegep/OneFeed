import SwiftUI
import SwiftData

struct CurrentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel = CurrentViewModel()
    @State private var readerArticle: Article?
    @State private var showingSources = false
    @State private var savePulse = 0
    @State private var showingSaveMark = false

    private var article: Article? { viewModel.currentArticle }

    private var excerpt: String? {
        guard let summary = article?.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty else { return nil }
        return summary
    }

    var body: some View {
        ZStack {
            OneFeedTheme.page.ignoresSafeArea()
            Group {
                if let article {
                    articleContent(article)
                        .id(article.id)
                        .transition(OneFeedMotion.cardTransition(reduceMotion: reduceMotion))
                } else {
                    caughtUp
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, OneFeedTheme.pagePadding)
            .padding(.bottom, 8)
            .animation(reduceMotion ? nil : OneFeedMotion.card, value: article?.id)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let article {
                articleActions(article)
            }
        }
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        .refreshProgressBanner(viewModel.progress)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isRefreshing {
                    Text(viewModel.progress.countText)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(viewModel.progress.accessibilityText())
                } else if let progress = viewModel.progressLabel {
                    Text(progress)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(viewModel.progressAccessibilityLabel ?? progress)
                }
            }
        }
        .task {
            viewModel.configure(with: modelContext)
            if !ProcessInfo.processInfo.arguments.contains("-uiTesting") {
                viewModel.startRefreshIfNeeded()
            }
        }
        .onOpenURL { url in
            guard url.scheme == "onefeed", url.host() == "reader", let article else { return }
            readerArticle = article
        }
        .refreshable { await refresh() }
        .sheet(isPresented: $showingSources) {
            NavigationStack {
                SourcesView()
            }
        }
        .fullScreenCover(item: $readerArticle) { article in
            ReaderView(article: article, onFinish: { state in
                readerArticle = nil
                transition(article, to: state)
            })
        }
        .sensoryFeedback(.success, trigger: savePulse)
        .alert("OneFeed", isPresented: Binding(get: { viewModel.presentedError != nil }, set: { if !$0 { viewModel.clearError() } })) {
            Button("OK", role: .cancel) { viewModel.clearError() }
        } message: { Text(viewModel.presentedError ?? "") }
    }

    @ViewBuilder
    private func articleContent(_ article: Article) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(article.feed?.title ?? "Source")
                .font(.subheadline.weight(.semibold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            if let kindLabel = mediumKindLabel(for: article) {
                Text(kindLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            Text(article.title)
                .font(.largeTitle.weight(.semibold))
                .tracking(-0.6)
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.78)
                .padding(.top, 14)
            if let excerpt {
                Text(excerpt)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .padding(.top, 16)
            }
            HStack(spacing: 8) {
                Text(article.publishedAt, format: .dateTime.month(.abbreviated).day())
                Text("·")
                Text(article.durationPhrase)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 18)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func mediumKindLabel(for article: Article) -> String? {
        switch article.contentKind {
        case "youtube": "Video"
        case "podcast": "Podcast"
        default: nil
        }
    }

    private func articleActions(_ article: Article) -> some View {
        VStack(spacing: 12) {
            Button("Read") { readerArticle = article }
                .buttonStyle(PrimaryActionStyle())
                .accessibilityHint("Opens the article reader")
            HStack(spacing: 10) {
                saveAction(article)
                secondaryAction("Skip", image: "forward", state: .skipped, article: article)
                secondaryAction("Done", image: "checkmark", state: .read, article: article)
            }
        }
        .padding(.horizontal, OneFeedTheme.pagePadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(OneFeedTheme.page)
        .overlay(alignment: .top) {
            if showingSaveMark {
                OneFeedMarkBurst(size: 22)
                    .offset(y: -6)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : OneFeedMotion.overlay, value: showingSaveMark)
    }

    private func saveAction(_ article: Article) -> some View {
        Button {
            savePulse += 1
            showingSaveMark = true
            transition(article, to: .saved)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(420))
                showingSaveMark = false
            }
        } label: {
            Label("Save", systemImage: "bookmark")
                .labelStyle(.titleAndIcon)
                .symbolEffect(.bounce, value: savePulse)
        }
        .buttonStyle(DecisionActionStyle())
        .accessibilityLabel("Save")
        .accessibilityHint(hint(for: .saved))
    }

    private func secondaryAction(_ label: String, image: String, state: ArticleState, article: Article) -> some View {
        Button {
            transition(article, to: state)
        } label: {
            Label(label, systemImage: image)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(DecisionActionStyle())
        .accessibilityLabel(label)
        .accessibilityHint(hint(for: state))
    }

    private func hint(for state: ArticleState) -> String {
        switch state {
        case .saved: "Saves this article for later"
        case .skipped: "Skips this article locally"
        case .read: "Marks this article done"
        default: ""
        }
    }

    private var caughtUp: some View {
        ContentUnavailableView {
            if viewModel.isRefreshing {
                Label {
                    Text(viewModel.progress.remainingText.isEmpty ? "Updating…" : viewModel.progress.remainingText)
                } icon: {
                    OneFeedMarkPulse(isActive: true, size: 36)
                }
            } else {
                Label("You're caught up.", systemImage: "checkmark.circle")
            }
        } description: {
            Text(viewModel.isRefreshing ? caughtUpProgressCopy : "Tomorrow gets a new stack.")
        } actions: {
            Button(viewModel.isRefreshing ? viewModel.progress.countText : "Refresh") { Task { await viewModel.refresh() } }
                .disabled(viewModel.isRefreshing)
                .frame(minHeight: 44)
            Button("Add a source") { showingSources = true }
                .frame(minHeight: 44)
        }
    }

    private var caughtUpProgressCopy: String {
        let detail = viewModel.progress.detailText()
        if detail.isEmpty { return "Fetching your sources. This can take a minute the first time." }
        return detail
    }

    private func transition(_ article: Article, to state: ArticleState) {
        withAnimation(reduceMotion ? nil : OneFeedMotion.card) {
            viewModel.transition(to: state)
        }
    }

    private func refresh() async {
        await viewModel.refresh()
    }
}
