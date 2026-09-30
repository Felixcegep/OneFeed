import Testing
@testable import OneFeed

struct ImportBatchResultTests {
    @Test func oneFailureKeepsItsSentence() {
        #expect(ImportBatchResult.message(succeeded: 0, failed: 1, firstFailure: "That file is empty.", emptyFallback: "Couldn’t add that to Queue.") == "That file is empty.")
    }

    @Test func aMixedBatchSaysHowManyLanded() {
        #expect(ImportBatchResult.message(succeeded: 2, failed: 1, firstFailure: "That file is empty.", emptyFallback: "Couldn’t add that to Queue.") == "Imported 2. 1 could not be imported.")
    }

    @Test func aCleanBatchSaysNothing() {
        #expect(ImportBatchResult.message(succeeded: 3, failed: 0, firstFailure: nil, emptyFallback: "Couldn’t add that to Queue.") == nil)
    }

    @Test func queueSuggestionsStopAtEight() {
        let articles = (0..<12).map { index in
            Article(guid: "\(index)", title: "Story \(index)", url: URL(string: "https://example.com/\(index)")!)
        }
        let shown = QueueFeedSuggestions.capped(articles)
        #expect(shown.count == QueueFeedSuggestions.shown)
        #expect(shown.first?.title == "Story 0")
        let withCopy = [Article(guid: "copy", title: "Copy", url: URL(string: "https://example.com/0")!)] + articles
        #expect(QueueFeedSuggestions.capped(withCopy).count == QueueFeedSuggestions.shown)
        #expect(QueueFeedSuggestions.capped(withCopy).map(\.id) == Array(ArticleIdentity.collapsingDuplicates(withCopy).prefix(QueueFeedSuggestions.shown)).map(\.id))
    }
}
