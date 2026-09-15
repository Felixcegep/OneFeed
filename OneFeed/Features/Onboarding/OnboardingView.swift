import SwiftUI

struct OnboardingView: View {
    let finish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel = OnboardingViewModel()
    @State private var starting = false
    @State private var appeared = false

    var body: some View {
        ZStack {
            OneFeedTheme.plaster.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 48)
                ZStack {
                    if starting {
                        OneFeedMarkBurst(size: 80)
                    } else {
                        OneFeedMark(size: 80)
                    }
                }
                .frame(height: 80)
                .padding(.bottom, 36)
                VStack(spacing: 16) {
                    Text(title)
                        .font(OneFeedTheme.serifDisplay(32))
                        .foregroundStyle(OneFeedTheme.ink)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.opacity)
                        .accessibilityAddTraits(.isHeader)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(OneFeedTheme.sansUI(17, weight: .regular))
                            .foregroundStyle(OneFeedTheme.graphite)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .contentTransition(.opacity)
                    }
                }
                .id(viewModel.page)
                .transition(.opacity)
                Spacer(minLength: 24)
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
                .padding(.bottom, 28)
                Button(viewModel.isLastPage ? "Start reading" : "Continue") {
                    advance()
                }
                .buttonStyle(PrimaryActionStyle())
                .disabled(starting)
                if viewModel.page == 1 {
                    Button("I’ll connect FreshRSS later") {
                        advance()
                    }
                    .font(OneFeedTheme.sansUI(15, weight: .regular))
                    .foregroundStyle(OneFeedTheme.graphite)
                    .frame(minHeight: 44)
                    .padding(.top, 8)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
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
        case 0: "One article."
        case 1: "A collection."
        default: "Read. Keep. Continue."
        }
    }

    private var subtitle: String {
        switch viewModel.page {
        case 0: "A short daily hanging, from sources you chose."
        case 1: "Add websites, RSS feeds, or connect FreshRSS in Settings."
        default: "Reader for the piece. Website when you want the original."
        }
    }
}
