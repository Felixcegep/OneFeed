import SwiftUI

/// Hairline under the nav bar. Always occupies 1pt so a short refresh does not shove the list.
struct RefreshProgressBanner: View {
    var progress: RefreshProgress

    var body: some View {
        ProgressView(value: progress.isActive ? progress.fraction : 0)
            .progressViewStyle(.linear)
            .tint(OneFeedTheme.accent)
            .transaction { $0.animation = nil }
            .opacity(progress.isActive ? 1 : 0)
            .animation(OneFeedMotion.overlay, value: progress.isActive)
            .frame(height: 1)
            .accessibilityHidden(!progress.isActive)
            .accessibilityLabel(progress.accessibilityText())
            .accessibilityAddTraits(progress.isActive ? .updatesFrequently : [])
    }
}

extension View {
    func refreshProgressBanner(_ progress: RefreshProgress) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            RefreshProgressBanner(progress: progress)
        }
    }
}
