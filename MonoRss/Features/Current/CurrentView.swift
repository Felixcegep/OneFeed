import SwiftUI
import SwiftData

struct CurrentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let openDestination: (AppDestination) -> Void
    @State private var viewModel = CurrentViewModel()
    @State private var readerArticle: Article?

    init(openDestination: @escaping (AppDestination) -> Void) {
        self.openDestination = openDestination
    }

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
                        .transition(.opacity)
                } else {
                    caughtUp
                }
            }
            .padding(.horizontal, OneFeedTheme.pagePadding)
            .padding(.bottom, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let article {
                articleActions(article)
            }
        }
        .navigationTitle("OneFeed")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { navigationMenu }
        .task {
            viewModel.configure(with: modelContext)
            if !ProcessInfo.processInfo.arguments.contains("-uiTesting") { await viewModel.refresh() }
        }
        .onOpenURL { url in
            guard url.scheme == "onefeed", url.host() == "reader", let article else { return }
            readerArticle = article
        }
        .refreshable { await refresh() }
        .fullScreenCover(item: $readerArticle) { article in
            ReaderView(article: article, onFinish: { state in
                readerArticle = nil
                transition(article, to: state)
            })
        }
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
                .accessibilityAddTraits(.isHeader)
            Text(article.title)
                .font(.largeTitle.weight(.semibold))
                .tracking(-0.6)
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.78)
                .padding(.top, 14)
                .accessibilityAddTraits(.isHeader)
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
                Text("\(article.estimatedReadingMinutes) min read")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 18)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func articleActions(_ article: Article) -> some View {
        VStack(spacing: 12) {
            Button("Read") { readerArticle = article }
                .buttonStyle(PrimaryActionStyle())
                .accessibilityHint("Opens the article reader")
            HStack(spacing: 10) {
                secondaryAction("Save", image: "bookmark", state: .saved, article: article)
                secondaryAction("Skip", image: "forward", state: .skipped, article: article)
                secondaryAction("Done", image: "checkmark", state: .read, article: article)
            }
        }
        .padding(.horizontal, OneFeedTheme.pagePadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(OneFeedTheme.page)
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
            Label("You're caught up.", systemImage: "checkmark.circle")
        } description: {
            Text("We'll keep an eye on your sources.")
        } actions: {
            Button(viewModel.isRefreshing ? "Refreshing…" : "Refresh") { Task { await viewModel.refresh() } }
                .disabled(viewModel.isRefreshing)
            Button("Add a source") { openDestination(.sources) }
        }
    }

    @ToolbarContentBuilder
    private var navigationMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Current", systemImage: "circle.fill") {}
                Divider()
                Button("Saved", systemImage: "bookmark") { openDestination(.saved) }
                Button("History", systemImage: "clock") { openDestination(.history) }
                Button("Sources", systemImage: "dot.radiowaves.left.and.right") { openDestination(.sources) }
                Divider()
                Button("Settings", systemImage: "gearshape") { openDestination(.settings) }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Open menu")
            .accessibilityIdentifier("current.navigationMenu")
        }
    }

    private func transition(_ article: Article, to state: ArticleState) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
            viewModel.transition(to: state)
        }
    }

    private func refresh() async {
        await viewModel.refresh()
    }
}
