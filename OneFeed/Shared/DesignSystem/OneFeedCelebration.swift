import SwiftUI

/// Particle burst in house colors. Duolingo / Strava fire this only on a real win,
/// at 400–700ms, with spring overshoot — never on Skip or routine taps.
struct OneFeedParticleBurst: View {
    enum Intensity {
        case small, medium, large

        var count: Int {
            switch self {
            case .small: 14
            case .medium: 26
            case .large: 42
            }
        }
    }

    var intensity: Intensity = .medium
    var isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var chips: [Chip] = []

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isActive || reduceMotion || chips.isEmpty)) { timeline in
                Canvas { context, size in
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    for chip in chips {
                        let age = now - chip.birth
                        guard age >= 0, age < chip.life else { continue }
                        let progress = age / chip.life
                        let x = chip.x + chip.vx * age
                        let y = chip.y + chip.vy * age + 210 * age * age
                        let angle = Angle.degrees(chip.rotation + chip.spin * age)
                        context.drawLayer { layer in
                            layer.opacity = Double(1 - progress)
                            layer.translateBy(x: x, y: y)
                            layer.rotate(by: angle)
                            let rect = CGRect(x: -chip.width / 2, y: -chip.height / 2, width: chip.width, height: chip.height)
                            layer.fill(Path(rect), with: .color(chip.color))
                        }
                    }
                }
            }
            .onAppear { if isActive { spawn(in: geo.size) } }
            .onChange(of: isActive) { _, active in
                if active { spawn(in: geo.size) }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func spawn(in size: CGSize) {
        guard !reduceMotion, isActive, size.width > 1 else {
            chips = []
            return
        }
        let now = Date.timeIntervalSinceReferenceDate
        let origin = CGPoint(x: size.width / 2, y: size.height / 2)
        let palette: [Color] = [
            OneFeedTheme.accent,
            Color.primary,
            Color.primary.opacity(0.38),
            Color(red: 0.72, green: 0.48, blue: 0.28),
            Color(red: 0.96, green: 0.93, blue: 0.88)
        ]
        chips = (0..<intensity.count).map { index in
            let angle = Double.random(in: 0..<(2 * .pi))
            let speed = Double.random(in: 90...260)
            return Chip(
                x: origin.x,
                y: origin.y,
                vx: CGFloat(cos(angle) * speed),
                vy: CGFloat(sin(angle) * speed - 80),
                birth: now + Double(index) * 0.006,
                life: Double.random(in: 0.55...0.85),
                width: CGFloat.random(in: 3...8),
                height: CGFloat.random(in: 8...16),
                rotation: Double.random(in: 0...360),
                spin: Double.random(in: -220...220),
                color: palette[index % palette.count]
            )
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            chips = []
        }
    }

    private struct Chip {
        var x, y, vx, vy: CGFloat
        var birth, life: TimeInterval
        var width, height: CGFloat
        var rotation, spin: Double
        var color: Color
    }
}
