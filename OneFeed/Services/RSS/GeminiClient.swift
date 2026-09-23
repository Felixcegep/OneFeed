import Foundation

enum GeminiClientError: LocalizedError, Equatable {
    case missingAPIKey
    case missingVideo
    case emptySummary
    case emptyReply
    case api(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add a Google AI Studio API key in Settings."
        case .missingVideo:
            "This item is missing a YouTube link."
        case .emptySummary:
            "Gemini returned an empty summary."
        case .emptyReply:
            "Gemini did not reply."
        case .api(let message):
            message
        }
    }
}

struct GeminiFunctionCall: Equatable, Sendable {
    var name: String
    var arguments: [String: String]

    func string(_ key: String) -> String? {
        let value = arguments[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    func bool(_ key: String) -> Bool? {
        guard let raw = arguments[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
            return nil
        }
        switch raw {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: return nil
        }
    }

    static func flatten(_ args: [String: Any]) -> [String: String] {
        args.reduce(into: [:]) { result, item in
            result[item.key] = stringify(item.value)
        }
    }

    static func stringify(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let bool as Bool:
            return bool ? "true" : "false"
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        case is NSNull:
            return ""
        default:
            guard JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value),
                  let string = String(data: data, encoding: .utf8) else {
                return String(describing: value)
            }
            return string
        }
    }
}

struct GeminiGenerateResult: Equatable, Sendable {
    var text: String
    var functionCalls: [GeminiFunctionCall]
    /// The model's `content` object, echoed on the next request so thought signatures survive.
    var modelContentJSON: Data

    var modelContent: [String: Any] {
        var object = (try? JSONSerialization.jsonObject(with: modelContentJSON)) as? [String: Any] ?? [:]
        if object["role"] == nil { object["role"] = "model" }
        return object
    }

    static func textReply(_ text: String) -> GeminiGenerateResult {
        let content: [String: Any] = ["role": "model", "parts": [["text": text]]]
        let data = (try? JSONSerialization.data(withJSONObject: content)) ?? Data()
        return GeminiGenerateResult(text: text, functionCalls: [], modelContentJSON: data)
    }

    static func toolCalls(_ calls: [GeminiFunctionCall]) -> GeminiGenerateResult {
        let parts: [[String: Any]] = calls.map { call in
            ["functionCall": ["name": call.name, "args": call.arguments]]
        }
        let content: [String: Any] = ["role": "model", "parts": parts]
        let data = (try? JSONSerialization.data(withJSONObject: content)) ?? Data()
        return GeminiGenerateResult(text: "", functionCalls: calls, modelContentJSON: data)
    }
}

struct GeminiInteractionReply: Equatable, Sendable {
    var id: String
    var text: String
}

protocol GeminiConversing: Sendable {
    func generateLibrarian(contentsJSON: Data, systemInstruction: String) async throws -> GeminiGenerateResult
}

private enum GeminiVideoTransportError: Error {
    case expiredInteraction
}

nonisolated struct GeminiClient: Sendable {
    private static let models = ["gemini-3.8-flash", "gemini-2.5-flash"]
    private static let videoSystemInstruction = """
    Answer only from the video, in the same language as the video. Cite timestamps as MM:SS. Do not invent facts. If the video does not cover the question, say so.
    """
    private static let summaryPrompt = """
    Write a summary of this video in the same language as the video.

    Make it short enough to read in a few minutes, and still carry every useful thing the video teaches. Keep the ideas, explanations, examples, names, and numbers that matter. Leave out repetition, asides, and filler.

    Write in clear, finished prose, the way a good essay would. Not an outline, and not a transcript.

    Use this shape:
    - One short opening paragraph on what the video is about.
    - Sections in the order of the video. Start each section with a heading line that begins with "## ", names the idea, and includes one MM:SS timestamp.
    - Under each heading, one or two paragraphs that carry the reasoning, steps, or examples.
    - A short closing paragraph for the conclusion.

    Do not add anything that is not in the video.
    """

    private let session: URLSession
    private let apiKey: @Sendable () -> String?

    init(session: URLSession = .shared, apiKey: @escaping @Sendable () -> String? = { GeminiAPIKeyStore.load() }) {
        self.session = session
        self.apiKey = apiKey
    }

    func summarizeYouTube(url: URL) async throws -> GeminiInteractionReply {
        guard let key = apiKey(), !key.isEmpty else { throw GeminiClientError.missingAPIKey }
        var lastError: Error = GeminiClientError.api("Gemini could not summarize this video.")
        for model in Self.models {
            do {
                let body = Self.summarizeYouTubeBody(model: model, videoURL: url)
                return try await postInteraction(
                    body: body,
                    apiKey: key,
                    previousInteractionIDSent: false,
                    emptyError: .emptySummary
                )
            } catch {
                lastError = error
                if case GeminiClientError.missingAPIKey = error { throw error }
                guard Self.failureIsModelUnavailable(error) else { throw error }
            }
        }
        throw lastError
    }

    func askYouTube(
        url: URL,
        question: String,
        previousInteractionID: String?,
        summary: String?,
        recentTurns: [VideoChatMessage]
    ) async throws -> GeminiInteractionReply {
        guard let key = apiKey(), !key.isEmpty else { throw GeminiClientError.missingAPIKey }
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else {
            throw GeminiClientError.api("Ask a question about the video.")
        }

        let storedID = previousInteractionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var sendVideoContext = storedID.isEmpty
        var lastError: Error = GeminiClientError.api("Gemini could not complete that request.")

        for model in Self.models {
            do {
                if !sendVideoContext {
                    let followUp = Self.askYouTubeFollowUpBody(
                        model: model,
                        question: trimmedQuestion,
                        previousInteractionID: storedID
                    )
                    do {
                        return try await postInteraction(
                            body: followUp,
                            apiKey: key,
                            previousInteractionIDSent: true,
                            emptyError: .emptyReply
                        )
                    } catch GeminiVideoTransportError.expiredInteraction {
                        sendVideoContext = true
                    }
                }

                let fallback = Self.askYouTubeFallbackBody(
                    model: model,
                    videoURL: url,
                    question: trimmedQuestion,
                    summary: summary,
                    recentTurns: recentTurns
                )
                return try await postInteraction(
                    body: fallback,
                    apiKey: key,
                    previousInteractionIDSent: false,
                    emptyError: .emptyReply
                )
            } catch {
                lastError = error
                if case GeminiClientError.missingAPIKey = error { throw error }
                guard Self.failureIsModelUnavailable(error) else { throw error }
            }
        }
        throw lastError
    }

    func generateLibrarian(contentsJSON: Data, systemInstruction: String) async throws -> GeminiGenerateResult {
        guard let key = apiKey(), !key.isEmpty else { throw GeminiClientError.missingAPIKey }
        var lastError: Error = GeminiClientError.api("Gemini could not complete that request.")
        for model in Self.models {
            do {
                return try await requestLibrarian(
                    model: model,
                    contentsJSON: contentsJSON,
                    systemInstruction: systemInstruction,
                    apiKey: key
                )
            } catch {
                lastError = error
                if case GeminiClientError.missingAPIKey = error { throw error }
            }
        }
        throw lastError
    }

    static func summarizeYouTubeBody(model: String, videoURL: URL) -> [String: Any] {
        videoBody(model: model, input: [
            textPart(summaryPrompt),
            videoPart(videoURL)
        ], maxOutputTokens: 2048)
    }

    static func askYouTubeFollowUpBody(
        model: String,
        question: String,
        previousInteractionID: String
    ) -> [String: Any] {
        var body = videoBody(model: model, input: question)
        body["previous_interaction_id"] = previousInteractionID
        return body
    }

    static func askYouTubeFallbackBody(
        model: String,
        videoURL: URL,
        question: String,
        summary: String?,
        recentTurns: [VideoChatMessage]
    ) -> [String: Any] {
        var input: [[String: Any]] = []
        let trimmedSummary = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedSummary.isEmpty {
            input.append(textPart(trimmedSummary))
        }
        for turn in recentTurns {
            let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let speaker = turn.role == .user ? "User" : "Model"
            input.append(textPart("\(speaker): \(text)"))
        }
        input.append(textPart(question))
        input.append(videoPart(videoURL))
        return videoBody(model: model, input: input)
    }

    /// Previous id was sent, and this response means that interaction is gone.
    /// A message that names a model is model-unavailable, including HTTP 404.
    static func isExpiredInteraction(statusCode: Int, body: Data, previousInteractionIDSent: Bool) -> Bool {
        guard previousInteractionIDSent else { return false }
        let message = interactionErrorMessage(in: body).lowercased()
        if message.contains("model") { return false }
        if statusCode == 404 { return true }
        if message.contains("previous_interaction") { return true }
        if message.contains("interaction"),
           message.contains("not found") || message.contains("expired") || message.contains("no longer") {
            return true
        }
        return false
    }

    static func parseSummary(from data: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiClientError.emptySummary
        }
        if let error = object["error"] as? [String: Any] {
            let message = (error["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GeminiClientError.api(message?.isEmpty == false ? message! : "Gemini could not summarize this video.")
        }
        let candidates = object["candidates"] as? [[String: Any]] ?? []
        let texts: [String] = candidates.flatMap { candidate in
            let content = candidate["content"] as? [String: Any]
            let parts = content?["parts"] as? [[String: Any]] ?? []
            return parts.compactMap { $0["text"] as? String }
        }
        let summary = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { throw GeminiClientError.emptySummary }
        return summary
    }

    static func parseInteraction(from data: Data, emptyError: GeminiClientError) throws -> GeminiInteractionReply {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw emptyError
        }
        if let error = object["error"] as? [String: Any] {
            let message = (error["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GeminiClientError.api(message?.isEmpty == false ? message! : "Gemini could not summarize this video.")
        }
        let id = (object["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !id.isEmpty else { throw emptyError }

        let steps = object["steps"] as? [[String: Any]] ?? []
        var texts: [String] = []
        for step in steps {
            guard (step["type"] as? String) == "model_output" else { continue }
            let content = step["content"] as? [[String: Any]] ?? []
            for item in content {
                guard (item["type"] as? String) == "text",
                      let text = item["text"] as? String else { continue }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { texts.append(trimmed) }
            }
        }
        let text = texts.joined(separator: "\n")
        guard !text.isEmpty else { throw emptyError }
        return GeminiInteractionReply(id: id, text: text)
    }

    static func parseGenerate(from data: Data) throws -> GeminiGenerateResult {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiClientError.emptyReply
        }
        if let error = object["error"] as? [String: Any] {
            let message = (error["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GeminiClientError.api(message?.isEmpty == false ? message! : "Gemini could not complete that request.")
        }
        let candidates = object["candidates"] as? [[String: Any]] ?? []
        guard let content = candidates.first?["content"] as? [String: Any] else {
            throw GeminiClientError.emptyReply
        }
        let parts = content["parts"] as? [[String: Any]] ?? []
        var texts: [String] = []
        var calls: [GeminiFunctionCall] = []
        for part in parts {
            if let text = part["text"] as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { texts.append(trimmed) }
            }
            if let call = part["functionCall"] as? [String: Any] {
                let name = (call["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !name.isEmpty else { continue }
                let args = call["args"] as? [String: Any] ?? [:]
                calls.append(GeminiFunctionCall(name: name, arguments: GeminiFunctionCall.flatten(args)))
            }
        }
        guard !texts.isEmpty || !calls.isEmpty else { throw GeminiClientError.emptyReply }
        let contentJSON = try JSONSerialization.data(withJSONObject: content)
        return GeminiGenerateResult(
            text: texts.joined(separator: "\n\n"),
            functionCalls: calls,
            modelContentJSON: contentJSON
        )
    }

    private static func videoBody(model: String, input: Any, maxOutputTokens: Int = 2048) -> [String: Any] {
        [
            "model": model,
            "system_instruction": videoSystemInstruction,
            "input": input,
            "generation_config": ["max_output_tokens": maxOutputTokens]
        ]
    }

    private static func textPart(_ text: String) -> [String: Any] {
        ["type": "text", "text": text]
    }

    private static func videoPart(_ url: URL) -> [String: Any] {
        ["type": "video", "uri": url.absoluteString]
    }

    private static func interactionErrorMessage(in body: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return String(data: body, encoding: .utf8) ?? ""
        }
        guard let error = object["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return ""
        }
        return message
    }

    private static func failureIsModelUnavailable(_ error: Error) -> Bool {
        guard case GeminiClientError.api(let message) = error else { return false }
        return message == "Model unavailable"
    }

    private func postInteraction(
        body: [String: Any],
        apiKey: String,
        previousInteractionIDSent: Bool,
        emptyError: GeminiClientError
    ) async throws -> GeminiInteractionReply {
        guard let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions") else {
            throw GeminiClientError.api("Invalid Gemini endpoint.")
        }
        var request = URLRequest(url: endpoint, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if Self.isExpiredInteraction(
            statusCode: status,
            body: data,
            previousInteractionIDSent: previousInteractionIDSent
        ) {
            throw GeminiVideoTransportError.expiredInteraction
        }
        if status == 404 {
            throw GeminiClientError.api("Model unavailable")
        }
        if status >= 400 {
            let message = Self.interactionErrorMessage(in: data).trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = emptyError == .emptySummary
                ? "Gemini could not summarize this video."
                : "Gemini could not complete that request."
            throw GeminiClientError.api(message.isEmpty ? fallback : message)
        }
        return try Self.parseInteraction(from: data, emptyError: emptyError)
    }

    private func requestLibrarian(
        model: String,
        contentsJSON: Data,
        systemInstruction: String,
        apiKey: String
    ) async throws -> GeminiGenerateResult {
        guard let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw GeminiClientError.api("Invalid Gemini endpoint.")
        }
        var request = URLRequest(url: endpoint, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let contents = try JSONSerialization.jsonObject(with: contentsJSON)
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": systemInstruction]]],
            "contents": contents,
            "tools": [["functionDeclarations": GeminiLibraryTools.declarations]],
            "toolConfig": ["functionCallingConfig": ["mode": "AUTO"]],
            "generationConfig": [
                "temperature": 0.4,
                "maxOutputTokens": 2048
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            throw GeminiClientError.api("Model unavailable")
        }
        return try Self.parseGenerate(from: data)
    }
}

extension GeminiClient: GeminiConversing {}
