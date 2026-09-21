import Foundation

nonisolated struct YouTubeMetadataService: Sendable {
    private static let maxWatchBytes = 2_500_000
    private static let browserUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1"
    private static let androidUserAgent = "com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip"
    private static let lengthQuotedPattern = #/"lengthSeconds"\s*:\s*"(\d+)"/#
    private static let lengthUnquotedPattern = #/"lengthSeconds"\s*:\s*(\d+)/#
    private static let approxDurationPattern = #/"approxDurationMs"\s*:\s*"(\d+)"/#
    private static let isoDurationPattern = #/itemprop="duration"\s+content="([^"]+)"/#

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchDuration(videoID: String, allowWatchHTML: Bool = true) async -> Int? {
        let trimmed = videoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 11 else { return nil }
        if let duration = await fetchDurationFromPlayerAPI(videoID: trimmed) {
            return duration
        }
        guard allowWatchHTML else { return nil }
        return await fetchDurationFromWatchPage(videoID: trimmed)
    }

    func fetchDurationFromPlayerAPI(videoID: String) async -> Int? {
        guard let url = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.androidUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        let body: [String: Any] = [
            "videoId": videoID,
            "contentCheckOk": true,
            "racyCheckOk": true,
            "context": [
                "client": [
                    "clientName": "ANDROID",
                    "clientVersion": "20.10.38",
                    "androidSdkVersion": 34,
                    "hl": "en",
                    "gl": "US"
                ]
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return Self.parseDuration(fromPlayerJSON: data)
        } catch {
            return nil
        }
    }

    private func fetchDurationFromWatchPage(videoID: String) async -> Int? {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(videoID)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("CONSENT=YES+; SOCS=CAI", forHTTPHeaderField: "Cookie")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let capped = data.prefix(Self.maxWatchBytes)
            guard let html = String(data: capped, encoding: .utf8) else { return nil }
            return Self.parseDuration(fromWatchHTML: html)
        } catch {
            return nil
        }
    }

    static func parseDuration(fromPlayerJSON data: Data) -> Int? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return parseDuration(fromPlayerObject: object)
    }

    static func parseDuration(fromPlayerObject object: [String: Any]) -> Int? {
        if let details = object["videoDetails"] as? [String: Any],
           let value = intValue(details["lengthSeconds"]), value > 0 {
            return value
        }
        if let streaming = object["streamingData"] as? [String: Any] {
            let collections = ["formats", "adaptiveFormats"]
            for key in collections {
                guard let formats = streaming[key] as? [[String: Any]] else { continue }
                for format in formats {
                    if let ms = intValue(format["approxDurationMs"]), ms > 0 {
                        return max(1, ms / 1000)
                    }
                }
            }
        }
        return nil
    }

    static func parseDuration(fromWatchHTML html: String) -> Int? {
        if let markerRange = html.range(of: "ytInitialPlayerResponse") {
            let tail = html[markerRange.upperBound...]
            if let eqRange = tail.range(of: "=") {
                var jsonStart = tail[eqRange.upperBound...]
                while let first = jsonStart.first, first.isWhitespace {
                    jsonStart = jsonStart.dropFirst()
                }
                if let jsonData = extractJSONObjectPrefix(from: jsonStart),
                   let duration = parseDuration(fromPlayerJSON: jsonData) {
                    return duration
                }
            }
        }
        if let match = html.firstMatch(of: lengthQuotedPattern), let value = Int(match.1), value > 0 {
            return value
        }
        if let match = html.firstMatch(of: lengthUnquotedPattern), let value = Int(match.1), value > 0 {
            return value
        }
        if let match = html.firstMatch(of: approxDurationPattern), let ms = Int(match.1), ms > 0 {
            return max(1, ms / 1000)
        }
        if let match = html.firstMatch(of: isoDurationPattern) {
            return parseISO8601Duration(String(match.1))
        }
        return nil
    }

    static func parseISO8601Duration(_ value: String) -> Int? {
        let upper = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard upper.hasPrefix("PT") else { return nil }
        let body = upper.dropFirst(2)
        var hours = 0, minutes = 0, seconds = 0
        var current = ""
        for character in body {
            if character.isNumber {
                current.append(character)
            } else if let amount = Int(current) {
                switch character {
                case "H": hours = amount
                case "M": minutes = amount
                case "S": seconds = amount
                default: break
                }
                current = ""
            }
        }
        let total = hours * 3600 + minutes * 60 + seconds
        return total > 0 ? total : nil
    }

    private static func intValue(_ raw: Any?) -> Int? {
        switch raw {
        case let value as Int: return value
        case let value as Int64: return Int(value)
        case let value as NSNumber: return value.intValue
        case let value as String: return Int(value)
        default: return nil
        }
    }

    private static func extractJSONObjectPrefix(from text: Substring, maxCharacters: Int = 400_000) -> Data? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = start
        var count = 0
        while index < text.endIndex, count < maxCharacters {
            let character = text[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    let end = text.index(after: index)
                    return String(text[start..<end]).data(using: .utf8)
                }
            }
            text.formIndex(after: &index)
            count += 1
        }
        return nil
    }
}
