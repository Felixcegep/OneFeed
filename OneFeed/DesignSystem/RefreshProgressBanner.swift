import SwiftUI

/// A slim progress line pinned to the top safe-area bar, outside the scrolling content.
struct RefreshProgressBanner: View {
    var progress: RefreshProgress
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown = false

    var body: some View {
        ZStack(alignment: .leading) {
            if isShown {
                Rectangle()
                    .fill(OneFeedTheme.accent)
                    .scaleEffect(x: max(progress.displayedFraction, 0.04), y: 1, anchor: .leading)
            }
        }
        .frame(height: isShown ? 2 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .animation(reduceMotion ? nil : OneFeedMotion.overlay, value: isShown)
        .animation(nil, value: progress.displayedFraction)
        .allowsHitTesting(false)
            .accessibilityHidden(!isShown)
            .accessibilityLabel(progress.accessibilityText())
            .accessibilityAddTraits(isShown ? .updatesFrequently : [])
            .task(id: progress.isActive) {
                guard progress.isActive else {
                    isShown = false
                    return
                }
                try? await Task.sleep(for: .milliseconds(160))
                guard !Task.isCancelled, progress.isActive else { return }
                isShown = true
            }
    }
}

extension View {
    /// Pins the refresh line to the navigation chrome so scroll-to-top cannot draw it across titles or rows.
    func refreshProgressBanner(_ progress: RefreshProgress) -> some View {
        safeAreaBar(edge: .top, spacing: 0) {
            RefreshProgressBanner(progress: progress)
        }
    }
}
