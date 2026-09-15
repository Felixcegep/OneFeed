import SwiftUI

/// Tiny terracotta burst for Save only. 400–700ms, then gone. Never on Skip or inbox-zero.
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
                        let y = chip.y + chip.vy * age + 160 * age * age
                        let angle = Angle.degrees(chip.rotation + chip.spin * age)
                        context.drawLayer { layer in
                            layer.opacity = Double(1 - progress)
                            layer.translateBy(x: x, y: y)
                            layer.rotate(by: angle)
                            let rect = CGRect(x: -chip.width / 2, y: -chip.height / 2, width: chip.width, height: chip.height)
                            layer.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(chip.color))
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
            OneFeedTheme.accentSoft,
            OneFeedTheme.ink.opacity(0.35),
            OneFeedTheme.sand
        ]
        chips = (0..<intensity.count).map { index in
            let angle = Double.random(in: 0..<(2 * .pi))
            let speed = Double.random(in: 60...140)
            return Chip(
                x: origin.x,
                y: origin.y,
                vx: CGFloat(cos(angle) * speed),
                vy: CGFloat(sin(angle) * speed - 40),
                birth: now + Double(index) * 0.008,
                life: Double.random(in: 0.4...0.7),
                width: CGFloat.random(in: 3...6),
                height: CGFloat.random(in: 3...8),
                rotation: Double.random(in: 0...360),
                spin: Double.random(in: -120...120),
                color: palette[index % palette.count]
            )
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
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
