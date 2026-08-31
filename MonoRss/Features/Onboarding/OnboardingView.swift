import SwiftUI

struct OnboardingView: View {
    let finish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel = OnboardingViewModel()

    var body: some View {
        ZStack {
            OneFeedTheme.page.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer(minLength: 24)
                OneFeedMarkPulse(isActive: viewModel.page == 0, size: 56)
                    .padding(.bottom, 8)
                VStack(spacing: 16) {
                    Text(title)
                        .font(.largeTitle.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                        .accessibilityAddTraits(.isHeader)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                }
                .id(viewModel.page)
                .transition(.opacity)
                Spacer(minLength: 16)
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(index == viewModel.page ? Color.primary : Color.secondary.opacity(0.28))
                            .frame(width: index == viewModel.page ? 18 : 7, height: 7)
                            .accessibilityHidden(true)
                    }
                }
                .animation(reduceMotion ? nil : OneFeedMotion.dots, value: viewModel.page)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Page \(viewModel.page + 1) of 3")
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
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                }
            }
            .padding(OneFeedTheme.pagePadding)
        }
    }

    private var title: String {
        switch viewModel.page {
        case 0: "A small daily stack."
        case 1: "Follow what matters."
        default: "Read, save, skip, done. Then the next card."
        }
    }

    private var subtitle: String {
        switch viewModel.page {
        case 0: "About ten things from sources you chose—never an overflowing inbox."
        case 1: "Add websites, RSS feeds, or connect FreshRSS in Settings."
        default: ""
        }
    }
}
