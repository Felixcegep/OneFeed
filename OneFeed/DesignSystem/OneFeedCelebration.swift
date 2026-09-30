import SwiftUI

/// Tiny terracotta burst for Save only. One shot, then gone. Never on Skip or inbox-zero.
struct OneFeedParticleBurst: View {
    enum Intensity {
        case small, medium, large

        var count: Int {
            switch self {
            case .small: 8
            case .medium: 12
            case .large: 16
            }
        }
    }

    var intensity: Intensity = .small
    var isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var chips: [Chip] = []
    @State private var flown = false
    @State private var flight: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(chips) { chip in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(chip.color)
                        .frame(width: chip.width, height: chip.height)
                        .rotationEffect(.degrees(flown ? chip.endRotation : chip.rotation))
                        .offset(x: flown ? chip.dx : 0, y: flown ? chip.dy : 0)
                        .opacity(flown ? 0 : 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { spawn(in: geo.size) }
            .onChange(of: isActive) { _, active in
                if active { spawn(in: geo.size) } else { clear() }
            }
            .onDisappear { clear() }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func spawn(in size: CGSize) {
        flight?.cancel()
        guard !reduceMotion, isActive, size.width > 1 else {
            clear()
            return
        }
        let palette: [Color] = [
            OneFeedTheme.accent,
            OneFeedTheme.accentSoft,
            OneFeedTheme.ink.opacity(0.35),
            OneFeedTheme.sand
        ]
        flown = false
        chips = (0..<intensity.count).map { index in
            let angle = Double.random(in: 0..<(2 * .pi))
            let distance = CGFloat.random(in: 36...88)
            return Chip(
                dx: CGFloat(cos(angle)) * distance,
                dy: CGFloat(sin(angle)) * distance - 28,
                width: CGFloat.random(in: 3...6),
                height: CGFloat.random(in: 3...8),
                rotation: Double.random(in: 0...360),
                endRotation: Double.random(in: -40...40),
                color: palette[index % palette.count]
            )
        }
        flight = Task { @MainActor in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.55)) {
                flown = true
            }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            clear()
        }
    }

    private func clear() {
        flight?.cancel()
        flight = nil
        chips = []
        flown = false
    }

    private struct Chip: Identifiable {
        let id = UUID()
        var dx, dy: CGFloat
        var width, height: CGFloat
        var rotation, endRotation: Double
        var color: Color
    }
}
