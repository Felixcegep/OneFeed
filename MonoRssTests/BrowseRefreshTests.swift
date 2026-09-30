import Foundation
import Testing
@testable import OneFeed

@MainActor
struct BrowseRefreshTests {
    @Test func feedSubtitleUsesAClockTimeInsteadOfARelativeMinute() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let fetched = now.addingTimeInterval(-120)
        let line = BrowseRefresh.updatedLine(at: fetched, now: now, calendar: calendar)
        let aMinuteLater = BrowseRefresh.updatedLine(at: fetched, now: now.addingTimeInterval(90), calendar: calendar)
        #expect(line == aMinuteLater)
        #expect(line.hasPrefix("Updated "))
        #expect(line.contains("ago") == false)
        #expect(BrowseRefresh.updatedLine(at: nil, now: now, calendar: calendar) == "Pull to update")
    }

    @Test func feedSubtitleMovesToYesterdayOnTheNextDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        #expect(BrowseRefresh.updatedLine(at: yesterday, now: now, calendar: calendar) == "Updated yesterday")
        let older = calendar.date(byAdding: .day, value: -3, to: now)!
        let olderLine = BrowseRefresh.updatedLine(at: older, now: now, calendar: calendar)
        #expect(olderLine != "Updated yesterday")
        #expect(olderLine.hasPrefix("Updated "))
    }

    @Test func aPassingMinuteDoesNotRewriteTheFeedSubtitle() {
        let refresh = BrowseRefresh()
        let calendar = Calendar.current
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let fetched = now.addingTimeInterval(-3_600)
        let feed = Feed(
            title: "Source",
            feedURL: URL(string: "https://source.test/rss")!,
            lastFetchedAt: fetched
        )
        refresh.adoptLatestFetch(from: [feed], now: now)
        let first = refresh.statusText
        #expect(first == BrowseRefresh.updatedLine(at: fetched, now: now, calendar: calendar))
        refresh.noteVisibleDay(now: now.addingTimeInterval(90), calendar: calendar)
        #expect(refresh.statusText == first)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: now)!
        refresh.noteVisibleDay(now: nextDay, calendar: calendar)
        #expect(refresh.statusText == "Updated yesterday")
    }
}
