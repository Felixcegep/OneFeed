import SwiftUI

struct VideoChatSheet: View {
    var viewModel: ReaderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(viewModel.videoChatMessages) { message in
                            messageRow(message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, OneFeedTheme.pagePadding)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                #if os(iOS)
                .scrollDismissesKeyboard(.interactively)
                #endif
                .onAppear { scrollToLatest(with: proxy) }
                .onChange(of: viewModel.videoChatMessages.last?.id) { _, _ in
                    scrollToLatest(with: proxy)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composer
            }
            .background(OneFeedTheme.plaster)
            .onDisappear { viewModel.cancelVideoWork() }
            .navigationTitle("This video")
            .oneFeedInlineTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .oneFeedMacSheetCanvas()
        #if os(iOS)
        .presentationBackground(OneFeedTheme.plaster)
        #endif
    }

    @ViewBuilder
    private func messageRow(_ message: VideoChatMessage) -> some View {
        switch message.role {
        case .model:
            Text(message.text)
                .font(.system(.body, design: .serif))
                .foregroundStyle(OneFeedTheme.ink)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .user:
            HStack(alignment: .bottom, spacing: 0) {
                Spacer(minLength: 36)
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(OneFeedTheme.ink)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        OneFeedTheme.paper,
                        in: RoundedRectangle(cornerRadius: OneFeedTheme.radius, style: .continuous)
                    )
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(OneFeedTheme.sand)
                .frame(height: 1)
            HStack(alignment: .center, spacing: 12) {
                TextField("Ask about this video", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundStyle(OneFeedTheme.ink)
                    .oneFeedSubmitGo()
                    .onSubmit { send() }
                if viewModel.isAskingVideo {
                    OneFeedMarkPulse(isActive: true, size: 18)
                        .accessibilityLabel("Asking")
                        .accessibilityAddTraits(.updatesFrequently)
                }
                Button("Send") { send() }
                    .font(.body.weight(.medium))
                    .foregroundStyle(OneFeedTheme.ink)
                    .frame(minHeight: 44)
                    .disabled(sendDisabled)
                    .opacity(sendDisabled ? 0.4 : 1)
            }
            .padding(.horizontal, OneFeedTheme.pagePadding)
            .padding(.vertical, 12)
            .background(OneFeedTheme.plaster)
        }
    }

    private var sendDisabled: Bool {
        viewModel.isAskingVideo || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard !viewModel.isAskingVideo else { return }
        let question = draft
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft = ""
        viewModel.beginVideoQuestion(question)
    }

    private func scrollToLatest(with proxy: ScrollViewProxy) {
        guard let id = viewModel.videoChatMessages.last?.id else { return }
        proxy.scrollTo(id, anchor: .bottom)
    }
}
