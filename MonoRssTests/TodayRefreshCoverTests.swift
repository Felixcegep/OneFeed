import Testing
@testable import OneFeed

struct TodayRefreshCoverTests {
    @Test func caughtUpRefreshKeepsTheScreen() {
        #expect(TodayRefreshCover.isShown(isRefreshing: true, hasStories: false, hasFeeds: true, skipsOpeningCover: false) == false)
    }

    @Test func theFirstLoadStillUsesTheCover() {
        #expect(TodayRefreshCover.isShown(isRefreshing: true, hasStories: false, hasFeeds: false, skipsOpeningCover: false))
        #expect(TodayRefreshCover.isShown(isRefreshing: true, hasStories: true, hasFeeds: false, skipsOpeningCover: false) == false)
        #expect(TodayRefreshCover.isShown(isRefreshing: false, hasStories: false, hasFeeds: false, skipsOpeningCover: false) == false)
    }
}
