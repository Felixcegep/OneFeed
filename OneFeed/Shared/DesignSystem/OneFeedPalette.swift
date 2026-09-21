import SwiftUI
#if os(macOS)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Frozen editorial palette. Neutrals carry the reading UI; hue is the remaining 10%.
///
/// Light values are the reviewed health-reader freeze. Dark values keep the same
/// earthy hues and are lifted so semantic *text* stays near 5:1 on `surface`.
enum OneFeedPalette: Sendable {
    struct Pair: Equatable, Sendable {
        let name: String
        let light: String
        let dark: String

        var css: String { "light-dark(\(light), \(dark))" }

        var color: Color {
            OneFeedPalette.adaptive(
                light: Self.rgb(light),
                dark: Self.rgb(dark),
                name: "OneFeed\(name)"
            )
        }

        static func rgb(_ hex: String) -> (CGFloat, CGFloat, CGFloat) {
            let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            let value = UInt32(digits, radix: 16) ?? 0
            return (
                CGFloat((value >> 16) & 0xFF) / 255,
                CGFloat((value >> 8) & 0xFF) / 255,
                CGFloat(value & 0xFF) / 255
            )
        }
    }

    // MARK: 90% interface

    static let canvas = Pair(name: "Canvas", light: "#F3EFE5", dark: "#1C1B18")
    static let surface = Pair(name: "Surface", light: "#FAF7F0", dark: "#252421")
    static let row = Pair(name: "Row", light: "#EAE4D9", dark: "#322F2A")
    /// Selected / current wash only. Never the sole state indicator.
    static let current = Pair(name: "Current", light: "#E2E9E2", dark: "#2A322C")
    static let text = Pair(name: "Text", light: "#171715", dark: "#F3EFE5")
    static let subdued = Pair(name: "Subdued", light: "#625F58", dark: "#B4B0A7")
    static let separator = Pair(name: "Separator", light: "#D8D2C7", dark: "#3E3B35")
    /// Icons and skip chrome. Not small body copy.
    static let stone = Pair(name: "Stone", light: "#7A756C", dark: "#9A968C")

    // MARK: 10% color

    static let link = Pair(name: "Link", light: "#355F59", dark: "#8FB8B2")
    static let saved = Pair(name: "Saved", light: "#52705B", dark: "#93B89C")
    static let clinical = Pair(name: "Clinical", light: "#52717A", dark: "#8FB4BC")
    static let research = Pair(name: "Research", light: "#835C1F", dark: "#D4A45A")
    static let wellness = Pair(name: "Wellness", light: "#626A4E", dark: "#A8B07C")
    static let attention = Pair(name: "Attention", light: "#A94F37", dark: "#E08A6E")
    static let destructive = Pair(name: "Destructive", light: "#A44535", dark: "#E07A6A")
    static let attentionSoft = Pair(name: "AttentionSoft", light: "#F0E4DC", dark: "#3D2A24")
    static let attentionPressed = Pair(name: "AttentionPressed", light: "#8C412D", dark: "#F0A088")

    static var readerRootCSS: String {
        """
          --paper: \(surface.css);
          --ink: \(text.css);
          --title: \(text.css);
          --meta: \(subdued.css);
          --rule: \(separator.css);
          --link: \(link.css);
          --quote: \(attention.css);
        """
    }

    fileprivate static func adaptive(
        light: (CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat),
        name: String
    ) -> Color {
        #if os(macOS)
        return Color(nsColor: NSColor(name: name, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: dark.0, green: dark.1, blue: dark.2, alpha: 1)
                : NSColor(srgbRed: light.0, green: light.1, blue: light.2, alpha: 1)
        }))
        #else
        _ = name
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: dark.0, green: dark.1, blue: dark.2, alpha: 1)
                : UIColor(red: light.0, green: light.1, blue: light.2, alpha: 1)
        })
        #endif
    }
}

extension Color {
    static var oneFeedPlaster: Color { OneFeedPalette.canvas.color }
    static var oneFeedPaper: Color { OneFeedPalette.surface.color }
    static var oneFeedWarm1: Color { OneFeedPalette.row.color }
    static var oneFeedCurrent: Color { OneFeedPalette.current.color }
    static var oneFeedInk: Color { OneFeedPalette.text.color }
    static var oneFeedGraphite: Color { OneFeedPalette.subdued.color }
    static var oneFeedSand: Color { OneFeedPalette.separator.color }
    static var oneFeedStone: Color { OneFeedPalette.stone.color }
    static var oneFeedLink: Color { OneFeedPalette.link.color }
    static var oneFeedSaved: Color { OneFeedPalette.saved.color }
    static var oneFeedClinical: Color { OneFeedPalette.clinical.color }
    static var oneFeedResearch: Color { OneFeedPalette.research.color }
    static var oneFeedWellness: Color { OneFeedPalette.wellness.color }
    static var oneFeedAttention: Color { OneFeedPalette.attention.color }
    static var oneFeedErrorText: Color { OneFeedPalette.destructive.color }
}
