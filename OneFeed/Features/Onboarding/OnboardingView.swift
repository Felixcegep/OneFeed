import SwiftUI

struct OnboardingView: View {
    let finish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel = OnboardingViewModel()
    @State private var starting = false

    var body: some View {
        ZStack {
            OneFeedTheme.plaster.ignoresSafeArea()
            OneFeedParticleBurst(intensity: .large, isActive: starting)
            VStack(spacing: 0) {
                Spacer(minLength: 48)
                ZStack {
                    if starting {
                        OneFeedMarkBurst(size: 88)
                    } else {
                        OneFeedMarkPulse(isActive: viewModel.page == 0, size: 88)
                    }
                }
                .frame(height: 88)
                .padding(.bottom, 36)
                VStack(spacing: 16) {
                    Text(title)
                        .font(.system(size: 34, weight: .regular, design: .serif))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.opacity)
                        .accessibilityAddTraits(.isHeader)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .contentTransition(.opacity)
                    }
                }
                .id(viewModel.page)
                .transition(.opacity)
                Spacer(minLength: 24)
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { index in
                        Rectangle()
                            .fill(index == viewModel.page ? Color.primary : Color.primary.opacity(0.18))
                            .frame(width: index == viewModel.page ? 18 : 6, height: 2)
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
                    .font(.footnote)
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    .padding(.top, 8)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
            .animation(reduceMotion ? nil : OneFeedMotion.page, value: viewModel.page)
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
