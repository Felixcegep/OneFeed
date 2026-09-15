import SwiftUI

/// Hairline progress under the navigation bar — Safari-style, not a card overlay.
struct RefreshProgressBanner: View {
    var progress: RefreshProgress

    var body: some View {
        if progress.isActive {
            ProgressView(value: progress.fraction)
                .progressViewStyle(.linear)
                .tint(OneFeedTheme.accent)
                .frame(height: 1)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityLabel(progress.accessibilityText())
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

extension View {
    func refreshProgressBanner(_ progress: RefreshProgress) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            RefreshProgressBanner(progress: progress)
                .animation(OneFeedMotion.overlay, value: progress.isActive)
        }
    }
}
