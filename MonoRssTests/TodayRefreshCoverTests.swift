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

    @Test func aLateCaptionWaitsForTheNextDeck() {
        let shownID = UUID()
        let waitingID = UUID()
        let known = [shownID: "Similar to something you read earlier today"]
        let visual = StoryCaptionPublish.visual(known: known, visibleIDs: [shownID, waitingID])
        #expect(visual == [shownID: "Similar to something you read earlier today"])
        #expect(visual[waitingID] == nil)
        #expect(SpokenCaption.value(spoken: "Similar to something you read earlier today", visible: nil) == "Similar to something you read earlier today")
        #expect(SpokenCaption.value(spoken: "Similar to something you read earlier today", visible: "Similar to something you read earlier today") == nil)
        #expect(SpokenCaption.value(spoken: nil, visible: nil) == nil)
        #expect(SpokenCaption.value(spoken: "", visible: nil) == nil)
    }

    @Test func anEmptyLibraryExplainsItselfBeforeThePlan() {
        #expect(LibraryHold.showsExplanation(hasStoredRows: false, ready: false, hasPlannedRows: false))
        #expect(LibraryHold.showsExplanation(hasStoredRows: true, ready: false, hasPlannedRows: false) == false)
        #expect(LibraryHold.showsExplanation(hasStoredRows: true, ready: true, hasPlannedRows: false))
        #expect(LibraryHold.showsExplanation(hasStoredRows: true, ready: true, hasPlannedRows: true) == false)
        #expect(LibraryHold.showsStoredRows(waiting: true, revealed: false) == false)
        #expect(LibraryHold.showsStoredRows(waiting: true, revealed: true))
        #expect(LibraryHold.showsStoredRows(waiting: false, revealed: true) == false)
        var scanned = false
        let known = LibraryHold.storedRowsAreKnown(
            planReady: true,
            provisionalHasRows: {
                scanned = true
                return false
            }(),
            plannedHasRows: false
        )
        #expect(known)
        #expect(scanned == false)
        #expect(LibraryHold.showsExplanation(hasStoredRows: known, ready: true, hasPlannedRows: false))
        var waitingScan = false
        #expect(LibraryHold.storedRowsAreKnown(
            planReady: false,
            provisionalHasRows: {
                waitingScan = true
                return true
            }(),
            plannedHasRows: false
        ))
        #expect(waitingScan)
        #expect(LibraryHold.storedRowsAreKnown(planReady: false, provisionalHasRows: false, plannedHasRows: false) == false)
    }

    @Test func theFirstLoadStillUsesTheCover() {
        #expect(TodayRefreshCover.isShown(isRefreshing: true, hasStories: false, hasFeeds: false, skipsOpeningCover: false))
        #expect(TodayRefreshCover.isShown(isRefreshing: true, hasStories: true, hasFeeds: false, skipsOpeningCover: false) == false)
        #expect(TodayRefreshCover.isShown(isRefreshing: false, hasStories: false, hasFeeds: false, skipsOpeningCover: false) == false)
    }
}
