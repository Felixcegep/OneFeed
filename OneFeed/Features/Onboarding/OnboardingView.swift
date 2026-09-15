import SwiftUI

struct OnboardingView: View {
    let finish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel = OnboardingViewModel()

    var body: some View {
        ZStack {
            OneFeedTheme.plaster.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 48)
                OneFeedMarkPulse(isActive: viewModel.page == 0, size: 88)
                    .padding(.bottom, 36)
                VStack(spacing: 16) {
                    Text(title)
                        .font(.system(size: 34, weight: .regular, design: .serif))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                        .accessibilityAddTraits(.isHeader)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
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
                    if viewModel.isLastPage {
                        finish()
                    } else if reduceMotion {
                        viewModel.advance()
                    } else {
                        withAnimation(OneFeedMotion.page) { viewModel.advance() }
                    }
                }
                .buttonStyle(PrimaryActionStyle())
                if viewModel.page == 1 {
                    Button("I’ll connect FreshRSS later") {
                        if reduceMotion {
                            viewModel.advance()
                        } else {
                            withAnimation(OneFeedMotion.page) { viewModel.advance() }
                        }
                    }
                    .font(.footnote)
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
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
