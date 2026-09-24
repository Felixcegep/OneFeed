import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Quiet paper motion: 200–350ms ease, one low-bounce spring for decisions.
enum OneFeedMotion {
    static let press = Animation.easeOut(duration: 0.2)
    static let card = Animation.easeInOut(duration: 0.3)
    static let list = Animation.easeInOut(duration: 0.3)
    static let overlay = Animation.easeOut(duration: 0.3)
    static let page = Animation.easeInOut(duration: 0.35)
    static let decision = Animation.spring(duration: 0.4, bounce: 0.12)
    static let reveal = Animation.easeOut(duration: 0.3)
    static let success = Animation.spring(duration: 0.4, bounce: 0.12)
    static let dots = Animation.easeInOut(duration: 0.2)

    static var allowsMotion: Bool {
        #if os(iOS)
        !UIAccessibility.isReduceMotionEnabled
        #elseif os(macOS)
        !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        true
        #endif
    }

    static func cardTransition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 6)),
            removal: .opacity
        )
    }

    /// Keep the curtain readable, then leave. Skip is immediate; Save may linger for a tiny burst.
    static func holdBeforeDismiss(reduceMotion: Bool, for state: ArticleState = .read) async {
        if reduceMotion || ProcessInfo.processInfo.arguments.contains("-uiTesting") { return }
        let milliseconds: Int = switch state {
        case .skipped: 180
        case .read: 320
        case .saved: 520
        default: 280
        }
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }
}

/// The OneFeed RSS mark, recast in attention on plaster.
struct OneFeedMark: View {
    var size: CGFloat = 28
    var arcProgress: CGFloat = 1
    var breathing: CGFloat = 1
    var dotScale: CGFloat = 1

    var body: some View {
        ZStack {
            RSSArc(radiusFraction: 0.34)
                .trim(from: 0, to: max(0.08, arcProgress))
                .stroke(OneFeedTheme.accent, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
            RSSArc(radiusFraction: 0.50)
                .trim(from: 0, to: max(0.08, arcProgress))
                .stroke(OneFeedTheme.accent, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
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

/// Thinking pulse: scale 1.0 → 1.15 and back. Still when inactive or Reduce Motion.
struct OneFeedMarkPulse: View {
    var isActive: Bool
    var size: CGFloat = 28
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    private var animates: Bool { isActive && !reduceMotion }

    var body: some View {
        OneFeedMark(size: size)
            .scaleEffect(animates && expanded ? 1.15 : 1)
            .animation(animates ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .easeOut(duration: 0.2), value: expanded)
            .onAppear { expanded = animates }
            .onChange(of: animates) { _, active in
                expanded = active
            }
            .accessibilityLabel(isActive ? "Updating" : "")
            .accessibilityAddTraits(isActive ? .updatesFrequently : [])
    }
}

/// Full-canvas wait: launch, reader WebKit, or a source refresh that still hitches.
struct OneFeedLoadingCover: View {
    var title: String
    var status: String
    var canvas: Color = OneFeedTheme.paper
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 20) {
            OneFeedMarkPulse(isActive: true, size: 52)
            Text(title)
                .font(.system(.title, design: .serif))
                .foregroundStyle(OneFeedTheme.ink)
                .multilineTextAlignment(.center)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 4)
                .fixedSize(horizontal: false, vertical: true)
            Text(status)
                .font(.body)
                .foregroundStyle(OneFeedTheme.graphite)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, OneFeedTheme.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(canvas)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(status)")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Quiet bloom for Save / add-source — scale in, no bounce carnival.
struct OneFeedMarkBurst: View {
    var size: CGFloat = 28
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popped = false

    var body: some View {
        OneFeedMark(size: size)
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

/// Brand lockup — terracotta RSS mark, serif name, stone tagline.
struct OneFeedBrandLockup: View {
    var markSize: CGFloat = 44
    var showsTagline = true

    var body: some View {
        VStack(spacing: 14) {
            OneFeedMark(size: markSize)
            VStack(spacing: 6) {
                Text("OneFeed")
                    .font(OneFeedTheme.serifDisplay(24))
                    .foregroundStyle(OneFeedTheme.ink)
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
        ZStack {
            Button("Refresh", systemImage: "arrow.clockwise", action: action)
                .foregroundStyle(OneFeedTheme.ink)
                .opacity(isRefreshing ? 0 : 1)
                .disabled(isRefreshing)
                .accessibilityHidden(isRefreshing)
            OneFeedMarkPulse(isActive: isRefreshing, size: 22)
                .opacity(isRefreshing ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(!isRefreshing)
                .accessibilityLabel("Updating")
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// Cream fade for Save / Skip / Done. Tiny burst only on Save. No chips on Skip.
struct OneFeedDecisionCurtain: View {
    let state: ArticleState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    @State private var showCaption = false

    var body: some View {
        ZStack {
            OneFeedTheme.plaster.opacity(visible ? 0.97 : 0)
            if shouldBurst {
                OneFeedParticleBurst(intensity: .small, isActive: visible)
            }
            VStack(spacing: 16) {
                artwork
                    .scaleEffect(visible ? 1 : 0.94)
                GalleryLabel(text: caption)
                    .opacity(showCaption ? 1 : 0)
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
        .onAppear {
            if reduceMotion {
                visible = true
                showCaption = true
                return
            }
            withAnimation(OneFeedMotion.decision) { visible = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                withAnimation(OneFeedMotion.overlay) { showCaption = true }
            }
        }
    }

    private var shouldBurst: Bool {
        !reduceMotion && state == .saved
    }

    @ViewBuilder
    private var artwork: some View {
        switch state {
        case .saved:
            OneFeedMarkBurst(size: 64)
        case .read:
            Image(systemName: "checkmark")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(OneFeedTheme.sage)
        case .skipped:
            Image(systemName: "forward")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(OneFeedTheme.stone)
        default:
            OneFeedMarkBurst(size: 64)
        }
    }

    private var caption: String {
        switch state {
        case .saved: "Queued"
        case .read: "Done"
        case .skipped: "Next"
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
