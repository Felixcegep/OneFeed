import SwiftUI

struct RefreshProgressBanner: View {
    var progress: RefreshProgress
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if progress.isActive {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                banner(now: timeline.date)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func banner(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                OneFeedMarkPulse(isActive: !reduceMotion, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(progress.primaryText)
                        .font(.subheadline.weight(.semibold))
                    if !progress.detailText(now: now).isEmpty {
                        Text(progress.detailText(now: now))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(progress.countText)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                    if !progress.remainingText.isEmpty {
                        Text(progress.remainingText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                }
            }
            ProgressView(value: progress.fraction)
                .tint(OneFeedTheme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OneFeedTheme.surface, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .padding(.horizontal, OneFeedTheme.pagePadding)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.accessibilityText(now: now))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

extension View {
    func refreshProgressBanner(_ progress: RefreshProgress) -> some View {
        overlay(alignment: .top) {
            RefreshProgressBanner(progress: progress)
                .animation(OneFeedMotion.overlay, value: progress.isActive)
        }
    }
}
