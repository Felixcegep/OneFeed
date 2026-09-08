import Foundation

enum GeminiClientError: LocalizedError, Equatable {
    case missingAPIKey
    case missingVideo
    case emptySummary
    case api(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add a Google AI Studio API key in Settings to summarize videos."
        case .missingVideo:
            "This item is missing a YouTube link."
        case .emptySummary:
            "Gemini returned an empty summary."
        case .api(let message):
            message
        }
    }
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
}
