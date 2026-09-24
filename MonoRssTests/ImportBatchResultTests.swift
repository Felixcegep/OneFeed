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
}
