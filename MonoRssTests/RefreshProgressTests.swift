import Foundation
import Testing
@testable import MonoRss

@MainActor
struct RefreshProgressTests {
    @Test func remainingPhraseCoversShortAndLongEstimates() {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(RefreshProgress.remainingPhrase(until: nil, now: now) == nil)
        #expect(RefreshProgress.remainingPhrase(until: now, now: now) == "almost done")
        #expect(RefreshProgress.remainingPhrase(until: now.addingTimeInterval(4), now: now) == "a few seconds left")
        #expect(RefreshProgress.remainingPhrase(until: now.addingTimeInterval(18), now: now) == "18s left")
        #expect(RefreshProgress.remainingPhrase(until: now.addingTimeInterval(90), now: now) == "about 2 min left")
    }

    @Test func finishItemCountsSourcesArticlesAndETA() {
        let progress = RefreshProgress()
        let start = Date(timeIntervalSince1970: 5_000)
        progress.begin(phase: .sources, total: 4, now: start)
        progress.startItem(title: "Aeon")
        progress.finishItem(newArticles: 3, now: start.addingTimeInterval(2))
        #expect(progress.completed == 1)
        #expect(progress.remainingCount == 3)
        #expect(progress.articlesFound == 3)
        #expect(progress.countText == "1 of 4")
        #expect(progress.remainingText == "3 left")
        #expect(progress.detailText(now: start.addingTimeInterval(2)).contains("3 new"))
        #expect(progress.estimatedFinish != nil)

        progress.startItem(title: "Trail of Bits")
        progress.finishItem(newArticles: 1, now: start.addingTimeInterval(4))
        #expect(progress.articlesFound == 4)
        #expect(progress.fraction == 0.5)
    }
}
