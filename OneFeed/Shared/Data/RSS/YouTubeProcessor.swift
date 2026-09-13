import Foundation

nonisolated enum YouTubeProcessor: Sendable {
    private static let watchVideoPattern = #/(?:v=|/embed/|/shorts/|/v/)([A-Za-z0-9_-]{11})/#
    private static let youtuBePattern = #/^/([A-Za-z0-9_-]{11})/#
    private static let channelPattern = #/(?:channel_id=|/channel/)(UC[A-Za-z0-9_-]+)/#

    static func parseVideoID(from url: URL?) -> String? {
        guard let url else { return nil }
        let host = url.host?.lowercased() ?? ""
        if host == "youtu.be" {
            let path = url.path
            if let match = path.firstMatch(of: youtuBePattern) {
                return String(match.1)
            }
        }
        if host == "youtube.com" || host.hasSuffix(".youtube.com") {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let videoID = components.queryItems?.first(where: { $0.name == "v" })?.value {
                let trimmed = String(videoID.prefix(11))
                return trimmed.count == 11 ? trimmed : nil
            }
            if let match = url.path.firstMatch(of: watchVideoPattern) {
                return String(match.1)
            }
        }
        return nil
    }

    static func parseVideoID(fromGUID guid: String) -> String? {
        let trimmed = guid.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["yt:video:", "tag:youtube.com,2008:video:"]
        for prefix in prefixes {
            if trimmed.lowercased().hasPrefix(prefix) {
                let id = String(trimmed.dropFirst(prefix.count).prefix(11))
                if id.count == 11 { return id }
            }
        }
        return parseVideoID(from: URL(string: trimmed))
    }

    static func parseChannelID(from url: URL?) -> String? {
        guard let url else { return nil }
        let absolute = url.absoluteString
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let channelID = components.queryItems?.first(where: { $0.name == "channel_id" })?.value {
            return channelID
        }
        if let match = absolute.firstMatch(of: channelPattern) {
            return String(match.1)
        }
        return nil
    }

    static func isShort(url: URL?, title: String = "") -> Bool {
        let path = url?.path.lowercased() ?? ""
        if path.contains("/shorts/") { return true }
        return title.lowercased().contains("#shorts")
    }

    static func watchURL(for videoID: String) -> URL? {
        guard videoID.count == 11 else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(videoID)")
    }

    static func embedURL(for videoID: String) -> URL? {
        guard videoID.count == 11 else { return nil }
        return URL(string: "https://www.youtube.com/embed/\(videoID)?playsinline=1")
    }

    static func thumbnailURL(for videoID: String) -> URL? {
        guard videoID.count == 11 else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")
    }

    static func shouldKeep(durationSeconds: Int?, minVideoSeconds: Int) -> Bool {
        guard let durationSeconds else { return true }
        return durationSeconds >= minVideoSeconds
    }

    /// Updates length in place. Too-short queued videos are skipped, never
    /// deleted — deleting a row the UI still holds crashes SwiftData.
    @discardableResult
    static func applyFetchedDuration(
        _ duration: Int,
        to article: Article,
        deckItems: [DailyDeckItem] = []
    ) -> Bool {
        guard duration > 0 else { return false }
        article.durationSeconds = duration
        article.estimatedReadingMinutes = ContentClassifier.consumeMinutes(
            entryType: .youtube,
            words: 0,
            durationSeconds: duration
        )
        let minSeconds = article.feed?.minVideoSeconds ?? 180
        guard !shouldKeep(durationSeconds: duration, minVideoSeconds: minSeconds) else { return false }
        if article.state == .saved || article.state == .current { return false }
        let isOnScreen = deckItems.contains { item in
            item.status == .current && item.article?.id == article.id
        }
        guard !isOnScreen else { return false }
        article.state = .skipped
        article.completedAt = article.completedAt ?? .now
        LibraryChange.note(article)
        for item in deckItems where item.article?.id == article.id && item.status == .queued {
            item.status = .skipped
        }
        return true
    }
}
