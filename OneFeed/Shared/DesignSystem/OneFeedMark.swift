import SwiftUI

/// Gallery pacing: springs for presses, slower fades for page changes. Interruptible.
enum OneFeedMotion {
    static let press = Animation.snappy(duration: 0.16)
    static let card = Animation.snappy(duration: 0.32)
    static let list = Animation.snappy(duration: 0.34)
    static let overlay = Animation.smooth(duration: 0.36)
    static let page = Animation.smooth(duration: 0.48)
    static let decision = Animation.smooth(duration: 0.42)
    static let reveal = Animation.smooth(duration: 0.5)
    static let success = Animation.smooth(duration: 0.52)
    static let dots = Animation.snappy(duration: 0.28)

    static func cardTransition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8)),
            removal: .opacity.combined(with: .offset(x: 12))
        )
    }

    static func holdBeforeDismiss(reduceMotion: Bool) async {
        if reduceMotion || ProcessInfo.processInfo.arguments.contains("-uiTesting") { return }
        try? await Task.sleep(for: .milliseconds(520))
    }
}

/// The OneFeed RSS mark: a small sculpture — ink arcs, one pigment origin.
struct OneFeedMark: View {
    var size: CGFloat = 28
    var arcProgress: CGFloat = 1
    var breathing: CGFloat = 1
    var dotScale: CGFloat = 1

    var body: some View {
        ZStack {
            RSSArc(radiusFraction: 0.34)
                .trim(from: 0, to: max(0.08, arcProgress))
                .stroke(Color.primary, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
            RSSArc(radiusFraction: 0.50)
                .trim(from: 0, to: max(0.08, arcProgress))
                .stroke(Color.primary, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
            Circle()
                .fill(OneFeedTheme.accent)
                .frame(width: size * 0.24, height: size * 0.24)
                .scaleEffect(dotScale)
                .position(x: size * 0.28, y: size * 0.72)
        }
        .frame(width: size, height: size)
        .scaleEffect(0.98 + 0.02 * breathing)
        .accessibilityHidden(true)
    }
}

/// Slow draw — the mark is the activity indicator, like a kinetic sculpture.
struct OneFeedMarkPulse: View {
    var isActive: Bool
    var size: CGFloat = 28
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !isActive || reduceMotion)) { timeline in
            let wave = (isActive && !reduceMotion) ? Self.wave(at: timeline.date) : 1
            OneFeedMark(
                size: size,
                arcProgress: 0.18 + (0.82 * wave),
                breathing: wave,
                dotScale: 0.92 + (0.1 * wave)
            )
            .opacity(0.55 + (0.45 * wave))
        }
        .accessibilityLabel(isActive ? "Updating" : "")
        .accessibilityAddTraits(isActive ? .updatesFrequently : [])
    }

    private static func wave(at date: Date) -> CGFloat {
        let period = 1.85
        let cycle = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period * 2)
        let linear = cycle < period ? cycle / period : 2 - cycle / period
        return linear * linear * (3 - 2 * linear)
    }
}

/// Quiet bloom for Save / add-source — no bounce.
struct OneFeedMarkBurst: View {
    var size: CGFloat = 28
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popped = false

    var body: some View {
        OneFeedMark(size: size, arcProgress: popped ? 1 : 0.2, breathing: 1, dotScale: popped ? 1.06 : 0.7)
            .scaleEffect(popped ? 1 : 0.86)
            .opacity(popped ? 1 : 0)
            .onAppear {
                if reduceMotion {
                    popped = true
                } else {
                    withAnimation(OneFeedMotion.success) { popped = true }
                }
            }
    }
}

/// Exhibition wordmark — serif title, tracked wall label.
struct OneFeedBrandLockup: View {
    var markSize: CGFloat = 44
    var showsTagline = true

    var body: some View {
        VStack(spacing: 14) {
            OneFeedMark(size: markSize)
            VStack(spacing: 6) {
                Text("OneFeed")
                    .font(.system(.title2, design: .serif))
                    .foregroundStyle(.primary)
                if showsTagline {
                    GalleryLabel(text: "One article at a time")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("OneFeed. One article at a time.")
    }
}

struct OneFeedToolbarRefresh: View {
    var isRefreshing: Bool
    var action: () -> Void

    var body: some View {
        Group {
            if isRefreshing {
                OneFeedMarkPulse(isActive: true, size: 22)
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("Updating")
                    .transition(.opacity)
            } else {
                Button("Refresh", systemImage: "arrow.clockwise", action: action)
            }
        }
        .animation(OneFeedMotion.overlay, value: isRefreshing)
    }
}

/// Plaster curtain for Save / Skip / Done — covers the piece, not a glass chip on the text.
struct OneFeedDecisionCurtain: View {
    let state: ArticleState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        ZStack {
            OneFeedTheme.plaster.opacity(visible ? 0.97 : 0)
            VStack(spacing: 18) {
                artwork
                GalleryLabel(text: caption)
                    .opacity(visible ? 1 : 0)
            }
            .scaleEffect(visible ? 1 : 0.92)
            .opacity(visible ? 1 : 0)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
        .onAppear {
            if reduceMotion {
                visible = true
            } else {
                withAnimation(OneFeedMotion.decision) { visible = true }
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        switch state {
        case .saved:
            OneFeedMarkBurst(size: 64)
        case .read:
            Image(systemName: "checkmark")
                .font(.system(size: 34, weight: .medium))
                .symbolEffect(.bounce, options: .nonRepeating, value: visible)
        case .skipped:
            Image(systemName: "forward")
                .font(.system(size: 32, weight: .medium))
                .symbolEffect(.bounce, options: .nonRepeating, value: visible)
        default:
            OneFeedMarkBurst(size: 64)
        }
    }

    private var caption: String {
        switch state {
        case .saved: "Kept"
        case .read: "Done"
        case .skipped: "Skipped"
        default: ""
        }
    }
}

private struct RSSArc: Shape {
    var radiusFraction: CGFloat

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.minX + side * 0.28, y: rect.minY + side * 0.72)
        var path = Path()
        path.addArc(
            center: origin,
            radius: side * radiusFraction,
            startAngle: .degrees(-92),
            endAngle: .degrees(2),
            clockwise: false
        )
        return path
    }
}
