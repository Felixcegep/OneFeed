import SwiftUI

struct OnboardingView: View {
    let finish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var viewModel = OnboardingViewModel()
    @State private var starting = false
    @State private var appeared = false

    var body: some View {
        ZStack {
            OneFeedTheme.plaster.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    if viewModel.canGoBack {
                        Button("Back") {
                            if reduceMotion {
                                viewModel.back()
                            } else {
                                withAnimation(OneFeedMotion.page) { viewModel.back() }
                            }
                        }
                        .font(.body)
                        .foregroundStyle(OneFeedTheme.graphite)
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                ScrollView {
                    VStack(spacing: 16) {
                        ZStack {
                            if starting {
                                OneFeedMarkBurst(size: 80)
                            } else {
                                OneFeedMark(size: 80)
                            }
                        }
                        .frame(height: 80)
                        .padding(.top, 24)
                        .padding(.bottom, 20)
                        Text(title)
                            .font(.system(.largeTitle, design: .serif))
                            .foregroundStyle(OneFeedTheme.ink)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentTransition(reduceMotion ? .identity : .opacity)
                            .accessibilityAddTraits(.isHeader)
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.body)
                                .foregroundStyle(OneFeedTheme.graphite)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 12)
                                .contentTransition(reduceMotion ? .identity : .opacity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 28)
                    .id(viewModel.page)
                    if dynamicTypeSize.isAccessibilitySize {
                        pageActions
                            .padding(.top, 28)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)

                if !dynamicTypeSize.isAccessibilitySize {
                    pageActions
                }
            }
            .opacity(appeared || reduceMotion ? 1 : 0)
            .animation(reduceMotion ? nil : OneFeedMotion.page, value: viewModel.page)
        }
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(OneFeedMotion.page) { appeared = true }
            }
        }
    }

    private var pageActions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index == viewModel.page ? OneFeedTheme.ink : OneFeedTheme.sand)
                        .frame(width: index == viewModel.page ? 18 : 6, height: 6)
                        .accessibilityHidden(true)
                }
            }
            .animation(reduceMotion ? nil : OneFeedMotion.dots, value: viewModel.page)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(viewModel.page + 1) of 3")
            .padding(.bottom, 20)
            Button {
                advance()
            } label: {
                Text(viewModel.isLastPage ? "Start reading" : "Continue")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .buttonStyle(PrimaryActionStyle())
            .disabled(starting)
            if viewModel.page == 1 {
                Button("I’ll connect FreshRSS later") {
                    advance()
                }
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(OneFeedTheme.graphite)
                .frame(minHeight: 44)
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 28)
    }

    private func advance() {
        if viewModel.isLastPage {
            starting = true
            Task { @MainActor in
                await OneFeedMotion.holdBeforeDismiss(reduceMotion: reduceMotion, for: .saved)
                finish()
            }
            return
        }
        if reduceMotion {
            viewModel.advance()
        } else {
            withAnimation(OneFeedMotion.page) { viewModel.advance() }
        }
    }

    private var title: String {
        switch viewModel.page {
        case 0: "Today, one piece."
        case 1: "Your RSS collection."
        default: "Read. Watch. Continue."
        }
    }

    private var subtitle: String {
        switch viewModel.page {
        case 0: "Read one story at a time in Today. Save stories in Queue for later."
        case 1: "Add websites, RSS feeds, or connect FreshRSS."
        default: "Open a piece when you are ready. Done when you are finished."
        }
    }
}
