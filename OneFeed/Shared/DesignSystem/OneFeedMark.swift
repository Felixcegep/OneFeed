import SwiftUI

enum OneFeedMotion {
    static let press = Animation.easeOut(duration: 0.14)
    static let card = Animation.easeOut(duration: 0.22)
    static let overlay = Animation.easeOut(duration: 0.2)
    static let page = Animation.easeOut(duration: 0.22)
    static let success = Animation.spring(response: 0.28, dampingFraction: 0.88)
    static let dots = Animation.spring(response: 0.32, dampingFraction: 0.86)

    static func cardTransition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 14)),
            removal: .opacity.combined(with: .offset(y: -10))
        )
    }
}

/// The OneFeed RSS mark: orange origin plus two radiating arcs, matching the app icon.
struct OneFeedMark: View {
    var size: CGFloat = 28
    var arcProgress: CGFloat = 1
    var breathing: CGFloat = 1
    var dotScale: CGFloat = 1

    var body: some View {
        ZStack {
            RSSArc(radiusFraction: 0.34)
                .trim(from: 0, to: max(0.08, arcProgress))
                .stroke(Color.primary, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
            RSSArc(radiusFraction: 0.50)
                .trim(from: 0, to: max(0.08, arcProgress))
                .stroke(Color.primary, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
            Circle()
                .fill(OneFeedTheme.accent)
                .frame(width: size * 0.26, height: size * 0.26)
                .scaleEffect(dotScale)
                .position(x: size * 0.28, y: size * 0.72)
        }
        .frame(width: size, height: size)
        .scaleEffect(0.96 + 0.04 * breathing)
        .accessibilityHidden(true)
    }
}

/// Looping draw-and-breathe used while feeds refresh or the reader extracts.
struct OneFeedMarkPulse: View {
    var isActive: Bool
    var size: CGFloat = 28
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isActive || reduceMotion)) { timeline in
            let wave = (isActive && !reduceMotion) ? Self.wave(at: timeline.date) : 1
            OneFeedMark(
                size: size,
                arcProgress: 0.28 + (0.72 * wave),
                breathing: wave,
                dotScale: 0.92 + (0.08 * wave)
            )
            .opacity(0.42 + (0.58 * wave))
        }
        .accessibilityLabel(isActive ? "Updating" : "")
        .accessibilityAddTraits(isActive ? .updatesFrequently : [])
    }

    private static func wave(at date: Date) -> CGFloat {
        let period = 0.9
        let cycle = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period * 2)
        let linear = cycle < period ? cycle / period : 2 - cycle / period
        return linear * linear * (3 - 2 * linear)
    }
}

/// One-shot pop for Save / add-source success.
struct OneFeedMarkBurst: View {
    var size: CGFloat = 28
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popped = false

    var body: some View {
        OneFeedMark(size: size, arcProgress: 1, breathing: 1, dotScale: popped ? 1.06 : 0.86)
            .scaleEffect(popped ? 1 : 0.92)
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
