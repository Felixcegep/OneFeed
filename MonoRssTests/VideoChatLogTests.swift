import Foundation
import Testing
@testable import OneFeed

struct VideoChatLogTests {
    @Test func roundTripPreservesMessagesIncludingTimestamps() {
        let created = Date(timeIntervalSince1970: 1_725_000_000)
        let messages = [
            VideoChatMessage(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                role: .user,
                text: "What happens at 14:37?",
                createdAt: created
            ),
            VideoChatMessage(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                role: .model,
                text: "At 14:37 the host explains the feed.",
                createdAt: created.addingTimeInterval(12)
            ),
        ]

        let decoded = VideoChatLog.decode(VideoChatLog.encode(messages))
        #expect(decoded == messages)
    }

    @Test func trimmedKeepsTheLastForty() {
        let messages = (0..<45).map { index in
            VideoChatMessage(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!,
                role: index.isMultiple(of: 2) ? .user : .model,
                text: "message \(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        let kept = VideoChatLog.trimmed(messages)
        #expect(kept.count == VideoChatLog.limit)
        #expect(kept.map(\.id) == Array(messages.suffix(40)).map(\.id))
        #expect(kept.map(\.id).contains(messages[0].id) == false)
        #expect(kept.map(\.id).contains(messages[4].id) == false)
        #expect(kept.first?.id == messages[5].id)
    }

    @Test func missingAndEmptyPayloads() {
        #expect(VideoChatLog.decode(nil).isEmpty)
        #expect(VideoChatLog.encode([]) == nil)
    }

    @Test func corruptDataDecodesToEmpty() {
        #expect(VideoChatLog.decode(Data("not-json".utf8)).isEmpty)
        #expect(VideoChatLog.decode(Data("{".utf8)).isEmpty)
    }
}
