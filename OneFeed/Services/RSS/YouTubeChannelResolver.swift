import Foundation

nonisolated enum YouTubeChannelResolver {
    static func feedURL(for channelID: String) -> URL? {
        guard channelID.range(of: #"^UC[A-Za-z0-9_-]{22}$"#, options: .regularExpression) != nil else { return nil }
        var components = URLComponents(string: "https://www.youtube.com/feeds/videos.xml")
        components?.queryItems = [URLQueryItem(name: "channel_id", value: channelID)]
        return components?.url
    }

    static func channelID(in html: String) -> String? {
        let patterns = [
            #"\"channelId\"\s*:\s*\"(UC[A-Za-z0-9_-]{22})\""#,
            #"\"externalId\"\s*:\s*\"(UC[A-Za-z0-9_-]{22})\""#,
            #"\"browseId\"\s*:\s*\"(UC[A-Za-z0-9_-]{22})\""#,
            #"\"channel_id\"\s*:\s*\"(UC[A-Za-z0-9_-]{22})\""#,
            #"itemprop=[\"']identifier[\"'][^>]*content=[\"'](UC[A-Za-z0-9_-]{22})[\"']"#,
            #"content=[\"'](UC[A-Za-z0-9_-]{22})[\"'][^>]*itemprop=[\"']identifier[\"']"#,
            #"itemprop=[\"']channelId[\"'][^>]*content=[\"'](UC[A-Za-z0-9_-]{22})[\"']"#,
            #"content=[\"'](UC[A-Za-z0-9_-]{22})[\"'][^>]*itemprop=[\"']channelId[\"']"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { continue }
            return String(html[range])
        }
        return nil
    }

    static func isChannelURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        guard host == "youtube.com" || host == "www.youtube.com" || host == "m.youtube.com" else { return false }
        return url.path.hasPrefix("/@") || url.path.hasPrefix("/channel/") || url.path.hasPrefix("/c/") || url.path.hasPrefix("/user/")
    }

    static func resolve(_ input: String, session: URLSession = .shared) async throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return input }
        let url: URL?
        if trimmed.hasPrefix("@") || (!trimmed.contains("://") && !trimmed.contains(".") && !trimmed.contains("/") && !trimmed.contains(" ")) {
            let handle = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
            guard !handle.isEmpty else { throw FeedServiceError.invalidAddress }
            if let feed = feedURL(for: handle) { return feed.absoluteString }
            url = URL(string: "https://www.youtube.com/@\(handle)")
        } else {
            url = FeedService.normalizedURL(from: trimmed)
        }
        guard let url, isChannelURL(url) else { return input }
        if let channelID = YouTubeProcessor.parseChannelID(from: url) {
            guard let feed = feedURL(for: channelID) else { throw FeedServiceError.invalidAddress }
            return feed.absoluteString
        }
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FeedServiceError.discoveryFailed
        }
        if let redirectedChannelID = YouTubeProcessor.parseChannelID(from: http.url),
           let feed = feedURL(for: redirectedChannelID) {
            return feed.absoluteString
        }
        guard let html = String(data: data.prefix(1_000_000), encoding: .utf8),
              let channelID = channelID(in: html), let feed = feedURL(for: channelID) else {
            throw FeedServiceError.discoveryFailed
        }
        return feed.absoluteString
    }
}
