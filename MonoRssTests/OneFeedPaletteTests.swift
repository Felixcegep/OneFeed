import Foundation
import Testing
@testable import OneFeed

struct OneFeedPaletteTests {
    @Test func frozenLightPaletteMatchesReview() {
        #expect(OneFeedPalette.canvas.light == "#F3EFE5")
        #expect(OneFeedPalette.surface.light == "#FAF7F0")
        #expect(OneFeedPalette.row.light == "#EAE4D9")
        #expect(OneFeedPalette.current.light == "#E2E9E2")
        #expect(OneFeedPalette.text.light == "#171715")
        #expect(OneFeedPalette.subdued.light == "#625F58")
        #expect(OneFeedPalette.separator.light == "#D8D2C7")
        #expect(OneFeedPalette.link.light == "#355F59")
        #expect(OneFeedPalette.saved.light == "#52705B")
        #expect(OneFeedPalette.clinical.light == "#52717A")
        #expect(OneFeedPalette.research.light == "#835C1F")
        #expect(OneFeedPalette.wellness.light == "#626A4E")
        #expect(OneFeedPalette.attention.light == "#A94F37")
        #expect(OneFeedPalette.destructive.light == "#A44535")
    }

    @Test func readingTextBeatsWCAGOnPaper() {
        let paper = OneFeedPalette.surface.light
        #expect(WCAGContrast.ratio(OneFeedPalette.text.light, paper) >= 4.5)
        #expect(WCAGContrast.ratio(OneFeedPalette.subdued.light, paper) >= 4.5)
        #expect(WCAGContrast.ratio(OneFeedPalette.link.light, paper) >= 5)
        #expect(WCAGContrast.ratio(OneFeedPalette.saved.light, paper) >= 5)
        #expect(WCAGContrast.ratio(OneFeedPalette.research.light, paper) >= 5)
        #expect(WCAGContrast.ratio(OneFeedPalette.wellness.light, paper) >= 5)
        #expect(WCAGContrast.ratio(OneFeedPalette.attention.light, paper) >= 5)
        #expect(WCAGContrast.ratio(OneFeedPalette.destructive.light, paper) >= 5)
    }

    @Test func darkSemanticTextBeatsFiveToOneOnSurface() {
        let paper = OneFeedPalette.surface.dark
        #expect(WCAGContrast.ratio(OneFeedPalette.text.dark, paper) >= 4.5)
        #expect(WCAGContrast.ratio(OneFeedPalette.subdued.dark, paper) >= 4.5)
        #expect(WCAGContrast.ratio(OneFeedPalette.link.dark, paper) >= 5)
        #expect(WCAGContrast.ratio(OneFeedPalette.saved.dark, paper) >= 5)
        #expect(WCAGContrast.ratio(OneFeedPalette.clinical.dark, paper) >= 5)
        #expect(WCAGContrast.ratio(OneFeedPalette.research.dark, paper) >= 5)
        #expect(WCAGContrast.ratio(OneFeedPalette.wellness.dark, paper) >= 5)
        #expect(WCAGContrast.ratio(OneFeedPalette.attention.dark, paper) >= 5)
        #expect(WCAGContrast.ratio(OneFeedPalette.destructive.dark, paper) >= 5)
    }

    @Test func increaseContrastMovesSecondaryTextTowardInk() {
        #expect(OneFeedPalette.subdued.contrastLight != OneFeedPalette.subdued.light)
        #expect(WCAGContrast.ratio(OneFeedPalette.subdued.contrastLight, OneFeedPalette.surface.light) > WCAGContrast.ratio(OneFeedPalette.subdued.light, OneFeedPalette.surface.light))
        #expect(WCAGContrast.ratio(OneFeedPalette.subdued.contrastDark, OneFeedPalette.surface.dark) > WCAGContrast.ratio(OneFeedPalette.subdued.dark, OneFeedPalette.surface.dark))
        #expect(OneFeedPalette.readerContrastCSS.contains("prefers-contrast: more"))
        #expect(OneFeedPalette.text.contrastLight == OneFeedPalette.text.light)
    }

    @Test func currentArticleUsesALabelNotOnlyColor() {
        let current = Article(guid: "now", title: "Current", state: .current)
        let queued = Article(guid: "later", title: "Queued", state: .queued)
        #expect(current.isCurrentReading)
        #expect(current.currentReadingLabel == "Now reading")
        #expect(queued.currentReadingLabel == nil)
    }
}

private enum WCAGContrast {
    static func ratio(_ hexA: String, _ hexB: String) -> Double {
        let first = luminance(hexA)
        let second = luminance(hexB)
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func luminance(_ hex: String) -> Double {
        let rgb = OneFeedPalette.Pair.rgb(hex)
        return 0.2126 * channel(rgb.0) + 0.7152 * channel(rgb.1) + 0.0722 * channel(rgb.2)
    }

    private static func channel(_ value: CGFloat) -> Double {
        let color = Double(value)
        return color <= 0.04045 ? color / 12.92 : pow((color + 0.055) / 1.055, 2.4)
    }
}
