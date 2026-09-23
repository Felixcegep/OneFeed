import SwiftUI

/// A slim progress line pinned to the top of the current screen.
struct RefreshProgressBanner: View {
    var progress: RefreshProgress
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ProgressView(value: progress.isActive ? progress.fraction : 0)
            .progressViewStyle(.linear)
            .tint(OneFeedTheme.accent)
            .transaction { $0.animation = nil }
            .opacity(progress.isActive ? 1 : 0)
            .animation(reduceMotion ? nil : OneFeedMotion.overlay, value: progress.isActive)
            .frame(height: 2)
            .accessibilityHidden(!progress.isActive)
            .accessibilityLabel(progress.accessibilityText())
            .accessibilityAddTraits(progress.isActive ? .updatesFrequently : [])
    }
}

extension View {
    func refreshProgressBanner(_ progress: RefreshProgress) -> some View {
        overlay(alignment: .top) {
            RefreshProgressBanner(progress: progress)
                .allowsHitTesting(false)
        }
    }
}
