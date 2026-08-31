import Foundation

nonisolated struct YouTubeMetadataService: Sendable {
    private static let maxWatchBytes = 2_500_000
    private static let userAgent = "OneFeed/1.0 (+local RSS aggregator)"
    private static let lengthPattern = #/"lengthSeconds"\s*:\s*"(\d+)"/#
    private static let isoDurationPattern = #/itemprop="duration"\s+content="([^"]+)"/#

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchDuration(videoID: String) async -> Int? {
        let trimmed = videoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 11 else { return nil }
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(trimmed)") else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html", forHTTPHeaderField: "Accept")

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

    static func parseDuration(fromWatchHTML html: String) -> Int? {
        if let markerRange = html.range(of: "ytInitialPlayerResponse") {
            let tail = html[markerRange.upperBound...]
            if let eqRange = tail.range(of: "=") {
                let jsonStart = tail[eqRange.upperBound...].trimmingCharacters(in: .whitespaces)
                if let jsonData = extractJSONObjectPrefix(from: String(jsonStart)),
                   let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let videoDetails = object["videoDetails"] as? [String: Any],
                   let raw = videoDetails["lengthSeconds"] {
                    let text = String(describing: raw)
                    if let value = Int(text) { return value }
                }
            }
        }
        if let match = html.firstMatch(of: lengthPattern) {
            return Int(match.1)
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

    private static func extractJSONObjectPrefix(from text: String) -> Data? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = start
        let characters = Array(text[start...])
        for (offset, character) in characters.enumerated() {
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 {
                    let end = text.index(start, offsetBy: offset + 1)
                    return String(text[start..<end]).data(using: .utf8)
                }
            }
        }
        return nil
    }
}
