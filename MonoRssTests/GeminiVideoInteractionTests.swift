import Foundation
import Testing
@testable import OneFeed

struct GeminiVideoInteractionTests {
    @Test func parseInteractionKeepsTimestampAndID() throws {
        let payload = """
        {
          "id": "v1_abc",
          "status": "completed",
          "steps": [
            {
              "type": "thought",
              "content": [{"type": "text", "text": "Planning the outline."}]
            },
            {
              "type": "model_output",
              "content": [
                {"type": "text", "text": "The claim lands at 14:37."}
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let reply = try GeminiClient.parseInteraction(from: payload, emptyError: .emptySummary)
        #expect(reply.id == "v1_abc")
        #expect(reply.text.contains("14:37"))
        #expect(!reply.text.contains("Planning"))
    }

    @Test func summarizeBodySendsVideoAndSectionPrompt() throws {
        let url = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
        let body = GeminiClient.summarizeYouTubeBody(model: "gemini-3.8-flash", videoURL: url)
        let object = try jsonObject(body)
        let input = try #require(object["input"] as? [[String: Any]])
        let video = try #require(input.first { $0["type"] as? String == "video" })
        let prompt = input.compactMap { $0["text"] as? String }.joined(separator: "\n")

        #expect(video["uri"] as? String == url.absoluteString)
        #expect(prompt.contains("every useful thing the video teaches"))
        #expect(prompt.contains("## "))
        #expect(prompt.contains("MM:SS"))
        #expect(prompt.contains("Not an outline, and not a transcript."))
        let config = try #require(object["generation_config"] as? [String: Any])
        #expect(config["max_output_tokens"] as? Int == 2048)
        #expect(object["previous_interaction_id"] == nil)
    }

    @Test func followUpBodyContinuesInteractionWithoutTheVideo() throws {
        let body = GeminiClient.askYouTubeFollowUpBody(
            model: "gemini-3.8-flash",
            question: "What was the main claim?",
            previousInteractionID: "v1_abc"
        )
        let data = try JSONSerialization.data(withJSONObject: body)
        let json = try #require(String(data: data, encoding: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["previous_interaction_id"] as? String == "v1_abc")
        #expect(object["input"] as? String == "What was the main claim?")
        #expect(json.contains("previous_interaction_id"))
        #expect(json.contains("What was the main claim?"))
        #expect(!json.lowercased().contains("youtube"))
        #expect(!json.contains("file_uri"))
        #expect(!json.contains("watch?v"))
    }

    @Test func expiredInteractionIsNotAMissingModel() throws {
        let expired = #"{"error":{"message":"Previous interaction not found"}}"#.data(using: .utf8)!
        #expect(
            GeminiClient.isExpiredInteraction(
                statusCode: 404,
                body: expired,
                previousInteractionIDSent: true
            )
        )

        let missingModel = #"{"error":{"message":"Model gemini-3.8-flash is not found"}}"#.data(using: .utf8)!
        #expect(
            !GeminiClient.isExpiredInteraction(
                statusCode: 404,
                body: missingModel,
                previousInteractionIDSent: true
            )
        )
    }

    @Test func fallbackBodyResendsSummaryTurnsQuestionAndVideo() throws {
        let url = URL(string: "https://www.youtube.com/watch?v=abc123xyz")!
        let turn = VideoChatMessage(
            id: UUID(),
            role: .user,
            text: "Who ran the experiment?",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let body = GeminiClient.askYouTubeFallbackBody(
            model: "gemini-2.5-flash",
            videoURL: url,
            question: "What was the result?",
            summary: "The lab compared two cooling methods.",
            recentTurns: [turn]
        )
        let object = try jsonObject(body)
        let input = try #require(object["input"] as? [[String: Any]])
        let video = try #require(input.first { $0["type"] as? String == "video" })
        let texts = input.compactMap { $0["text"] as? String }

        #expect(video["uri"] as? String == url.absoluteString)
        #expect(texts.contains("The lab compared two cooling methods."))
        #expect(texts.contains("User: Who ran the experiment?"))
        #expect(texts.contains("What was the result?"))
        #expect(object["previous_interaction_id"] == nil)
    }

    private func jsonObject(_ body: [String: Any]) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: body)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
