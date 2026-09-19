import Foundation
import Testing
@testable import OneFeed

struct ReaderFocusTests {
    @Test func defaultZoneSitsBetweenTopAndMiddle() {
        #expect(ReaderFocus.defaultZoneY == 0.37)
        #expect(ReaderFocus.clampZone(0) == ReaderFocus.minimumZoneY)
        #expect(ReaderFocus.clampZone(1) == ReaderFocus.maximumZoneY)
        #expect(ReaderFocus.clampZone(0.4) == 0.4)
    }

    @Test func surroundingTextStaysReadable() {
        let subtle = ReaderFocus.opacities(intensity: 0)
        #expect(subtle.previous == 1)
        #expect(subtle.next == 1)

        let strong = ReaderFocus.opacities(intensity: 1)
        #expect(strong.previous == 0.80)
        #expect(strong.near == 0.88)
        #expect(strong.next == 0.85)
        #expect(strong.previous >= 0.80)
        #expect(strong.next >= 0.80)
    }

    @Test func trailStoreRoundTripsAndSkipsTheStart() {
        let defaults = UserDefaults(suiteName: "ReaderFocusTests.\(UUID().uuidString)")!
        let articleID = UUID()
        let trail = ReadingTrail(
            articleID: articleID,
            blockIndex: 4,
            anchor: "The experiment resulted",
            scrollRatio: 0.42,
            zoneY: 0.37,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        ReadingTrailStore.save(trail, defaults: defaults)
        let loaded = ReadingTrailStore.load(articleID: articleID, defaults: defaults)
        #expect(loaded?.blockIndex == 4)
        #expect(loaded?.anchor == "The experiment resulted")
        #expect(loaded?.scrollRatio == 0.42)

        ReadingTrailStore.clear(articleID: articleID, defaults: defaults)
        #expect(ReadingTrailStore.load(articleID: articleID, defaults: defaults) == nil)

        let start = ReadingTrail(
            articleID: articleID,
            blockIndex: 0,
            anchor: "Hello",
            scrollRatio: 0.01,
            zoneY: 0.37,
            updatedAt: .now
        )
        #expect(start.isNearStart)
        let cfg = ReaderFocus.configuration(
            mode: .smart,
            intensity: 0.5,
            zoneY: 0.37,
            reduceMotion: false,
            trail: start
        )
        #expect(cfg["trail"] == nil)
    }

    @Test func snapshotParsesWebKitDictionaries() {
        let articleID = UUID()
        let trail = ReaderFocus.snapshot(
            from: [
                "blockIndex": 12,
                "anchor": String(repeating: "a", count: 80),
                "scrollRatio": 0.64,
                "zoneY": 0.41,
            ] as [String: Any],
            articleID: articleID,
            fallbackZoneY: 0.37
        )
        #expect(trail?.blockIndex == 12)
        #expect(trail?.anchor.count == 48)
        #expect(trail?.scrollRatio == 0.64)
        #expect(trail?.zoneY == 0.41)
    }

    @Test @MainActor func readerDocumentEmbedsFocusEngineAndKeepsArticleScriptsOut() {
        let article = Article(
            guid: "1",
            title: "Essay",
            contentHTML: #"<p>Hello reader</p><script>alert(1)</script><a href="javascript:alert(2)">x</a>"#
        )
        let html = ReaderViewModel(article: article).documentHTML(fontChoice: .serif, textSize: .standard)
        #expect(html.contains("id=\"onefeed-article\""))
        #expect(html.contains("window.OneFeedFocus"))
        #expect(html.contains("Hello reader"))
        #expect(html.contains("#onefeed-marker"))
        #expect(!html.contains("alert(1)"))
        #expect(!html.contains("javascript:alert(2)"))
    }

    @Test func sanitizerStripsJavascriptURLs() {
        let cleaned = ReaderHTML.sanitizedBody(#"<p><a href="javascript:alert(1)">Open</a></p>"#)
        #expect(!cleaned.contains("javascript:"))
        #expect(cleaned.contains("Open"))
    }
}
