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

protocol GeminiConversing: Sendable {
    func generateLibrarian(contentsJSON: Data, systemInstruction: String) async throws -> GeminiGenerateResult
}

nonisolated struct GeminiClient: Sendable {
    private static let models = ["gemini-2.5-flash", "gemini-2.0-flash"]
    private static let prompt = """
    Summarize this YouTube video in 4–6 short sentences. Cover the main claim, the important facts or steps, and the conclusion. Write in the same language as the video. Do not mention being an AI or that you watched a video.
    """

    private let session: URLSession
    private let apiKey: @Sendable () -> String?

    init(session: URLSession = .shared, apiKey: @escaping @Sendable () -> String? = { GeminiAPIKeyStore.load() }) {
        self.session = session
        self.apiKey = apiKey
    }

    func summarizeYouTube(url: URL) async throws -> String {
        guard let key = apiKey(), !key.isEmpty else { throw GeminiClientError.missingAPIKey }
        var lastError: Error = GeminiClientError.api("Gemini could not summarize this video.")
        for model in Self.models {
            do {
                return try await requestSummary(model: model, videoURL: url, apiKey: key)
            } catch {
                lastError = error
                if case GeminiClientError.missingAPIKey = error { throw error }
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

    private func requestSummary(model: String, videoURL: URL, apiKey: String) async throws -> String {
        guard let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw GeminiClientError.api("Invalid Gemini endpoint.")
        }
        var request = URLRequest(url: endpoint, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": Self.prompt],
                    ["file_data": ["file_uri": videoURL.absoluteString]]
                ]
            ]],
            "generationConfig": [
                "temperature": 0.3,
                "maxOutputTokens": 640
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            throw GeminiClientError.api("Model unavailable")
        }
        return try Self.parseSummary(from: data)
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
