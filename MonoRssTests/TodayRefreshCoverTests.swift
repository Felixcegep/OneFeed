import Testing
@testable import OneFeed

struct TodayRefreshCoverTests {
    @Test func caughtUpRefreshKeepsTheScreen() {
        #expect(TodayRefreshCover.isShown(isRefreshing: true, hasStories: false, hasFeeds: true, skipsOpeningCover: false) == false)
        #expect(TodayEmptyCopy.choose(
            isRefreshing: true,
            hasFeeds: true,
            todayHasNoSources: false,
            finishedSelection: true,
            celebrate: false
        ) == .caughtUp)
        #expect(TodayEmptyCopy.choose(
            isRefreshing: true,
            hasFeeds: true,
            todayHasNoSources: false,
            finishedSelection: false,
            celebrate: false
        ) == .updating)
    }

    @Test func advancingTheFeaturedCardKeepsItsPreview() {
        let firstID = UUID()
        let nextID = UUID()
        let first = FeaturedExcerptFrame(articleID: nil, text: nil)
            .advancing(to: firstID, preview: "The first blurb.")
        #expect(first == FeaturedExcerptFrame(articleID: firstID, text: "The first blurb."))
        let next = first.advancing(to: nextID, preview: "The next blurb.")
        #expect(next == FeaturedExcerptFrame(articleID: nextID, text: "The next blurb."))
        #expect(next.advancing(to: nil, preview: "Gone").text == nil)
    }

    @Test func theFirstLoadStillUsesTheCover() {
        #expect(TodayRefreshCover.isShown(isRefreshing: true, hasStories: false, hasFeeds: false, skipsOpeningCover: false))
        #expect(TodayRefreshCover.isShown(isRefreshing: true, hasStories: true, hasFeeds: false, skipsOpeningCover: false) == false)
        #expect(TodayRefreshCover.isShown(isRefreshing: false, hasStories: false, hasFeeds: false, skipsOpeningCover: false) == false)
    }
}
