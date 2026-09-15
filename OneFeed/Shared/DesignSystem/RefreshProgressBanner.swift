import SwiftUI

/// Hairline under the nav bar. Always occupies 1pt so a short refresh does not shove the list.
struct RefreshProgressBanner: View {
    var progress: RefreshProgress

    var body: some View {
        ProgressView(value: progress.isActive ? progress.fraction : 0)
            .progressViewStyle(.linear)
            .tint(OneFeedTheme.accent)
            .opacity(progress.isActive ? 1 : 0)
            .frame(height: 1)
            .animation(OneFeedMotion.overlay, value: progress.fraction)
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
