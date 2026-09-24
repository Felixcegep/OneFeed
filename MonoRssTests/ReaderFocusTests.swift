import Foundation
import Testing
@testable import OneFeed

struct ReaderFocusTests {
    @Test func resumeCueSitsAboveWhenTheBlockHasRoom() {
        let place = ReaderFocus.resumeCuePlacement(
            blockTop: 280,
            blockBottom: 360,
            labelHeight: 20,
            viewportHeight: 800
        )
        #expect(place == .above(top: 252))
    }

    @Test func resumeCueMovesBelowABlockNearTheTop() {
        let place = ReaderFocus.resumeCuePlacement(
            blockTop: 16,
            blockBottom: 48,
            labelHeight: 20,
            viewportHeight: 800
        )
        #expect(place == .below(top: 56))
    }

    @Test func resumeCueStaysHiddenWhenNeitherSideFits() {
        let place = ReaderFocus.resumeCuePlacement(
            blockTop: 12,
            blockBottom: 790,
            labelHeight: 20,
            viewportHeight: 800
        )
        #expect(place == .hidden)
    }

    @Test func resumeCueScriptUsesTheSameGaps() {
        let script = ReaderFocus.pageScript
        #expect(script.contains("edge: \"above\""))
        #expect(script.contains("edge: \"below\""))
        #expect(script.contains("edge: \"hidden\""))
        #expect(script.contains("box.top - height - \(Int(ReaderFocus.resumeCueGap))"))
        #expect(script.contains("above >= \(Int(ReaderFocus.resumeCueInset))"))
        #expect(ReaderFocus.pageCSS.contains("background: var(--paper)"))
        #expect(!script.contains("Math.max(12, box.top - 26)"))
    }

    @Test func pageSettleWaitsGrowThenLevelOff() {
        #expect(ReaderFocus.pageSettlePause(after: 0) == .milliseconds(80))
        #expect(ReaderFocus.pageSettlePause(after: 1) == .milliseconds(160))
        #expect(ReaderFocus.pageSettlePause(after: 2) == .milliseconds(320))
        #expect(ReaderFocus.pageSettlePause(after: 3) == .milliseconds(640))
        #expect(ReaderFocus.pageSettlePause(after: 4) == .milliseconds(1_000))
        #expect(ReaderFocus.pageSettlePause(after: 12) == .milliseconds(1_000))
        #expect(ReaderFocus.trailSnapshotInterval >= .seconds(8))
    }

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

    @Test @MainActor func lateDurationLeavesTheReaderPageInPlace() {
        let article = Article(
            guid: "yt",
            title: "Caches",
            contentKind: "youtube",
            contentHTML: "<p>Body</p>",
            durationSeconds: 0
        )
        let model = ReaderViewModel(article: article)
        let first = model.documentHTML(fontChoice: .serif, textSize: .standard)
        article.durationSeconds = 600
        let second = model.documentHTML(fontChoice: .serif, textSize: .standard)
        #expect(first == second)
        #expect(model.readerMetaLine.contains("10 min"))
        let resized = model.documentHTML(fontChoice: .serif, textSize: .large)
        #expect(resized != first)
        #expect(resized.contains("10 min"))
        let bold = model.documentHTML(fontChoice: .serif, textSize: .standard, boldText: true)
        #expect(bold != first)
        #expect(bold.contains("font-weight: 650"))
        #expect(model.readerLoadID(fontChoice: .serif, textSize: .standard) == model.readerLoadID(fontChoice: .serif, textSize: .standard))
    }

    @Test @MainActor func readerDocumentBuiltOffTheMainThreadMatchesTheCachedPage() async {
        let article = Article(
            guid: "off-main",
            title: "Essay",
            contentHTML: #"<p>Hello reader</p><script>alert(1)</script>"#
        )
        let model = ReaderViewModel(article: article)
        let built = await model.loadDocumentHTML(fontChoice: .serif, textSize: .standard)
        let cached = model.documentHTML(fontChoice: .serif, textSize: .standard)
        #expect(built == cached)
        #expect(built.contains("Hello reader"))
        #expect(!built.contains("alert(1)"))
        let loadID = model.readerLoadID(fontChoice: .serif, textSize: .standard)
        article.durationSeconds = 600
        #expect(model.readerLoadID(fontChoice: .serif, textSize: .standard) == loadID)
    }

    @Test @MainActor func whitespaceOnlyBodyUsesTheMetadataFallback() async {
        let article = Article(guid: "blank", title: "Empty", contentHTML: "   \n")
        let model = ReaderViewModel(article: article)
        let html = model.documentHTML(fontChoice: .serif, textSize: .standard)
        let built = await model.loadDocumentHTML(fontChoice: .serif, textSize: .standard)
        #expect(html.contains("only provided metadata"))
        #expect(built == html)
    }

    @Test @MainActor func youtubeWithVisibleSummaryOpensInTheReader() {
        #expect(ReaderView.youtubeOpensInReader(summary: "  A real summary") == true)
        #expect(ReaderView.youtubeOpensInReader(summary: " \n\t") == false)
        #expect(ReaderView.youtubeOpensInReader(summary: nil) == false)
        let article = Article(guid: "yt-blank", title: "Talk", contentKind: "youtube", aiSummary: " \n")
        let model = ReaderViewModel(article: article)
        #expect(model.hasAISummary == false)
        article.aiSummary = "A point worth keeping"
        #expect(model.hasAISummary == true)
    }

    @Test @MainActor func replacingTheArticleBodyRebuildsThePage() {
        let article = Article(
            guid: "essay",
            title: "Caches",
            contentHTML: "<p>The first page.</p>"
        )
        let model = ReaderViewModel(article: article)
        let first = model.documentHTML(fontChoice: .serif, textSize: .standard)
        let second = model.documentHTML(fontChoice: .serif, textSize: .standard)
        #expect(first == second)
        article.contentHTML = "<p>The revised page.</p>"
        let revised = model.documentHTML(fontChoice: .serif, textSize: .standard)
        #expect(revised != first)
        #expect(revised.contains("The revised page."))
        #expect(!revised.contains("The first page."))
    }

    @Test func sanitizerStripsJavascriptURLs() {
        let cleaned = ReaderHTML.sanitizedBody(#"<p><a href="javascript:alert(1)">Open</a></p>"#)
        #expect(!cleaned.contains("javascript:"))
        #expect(cleaned.contains("Open"))
    }
}
