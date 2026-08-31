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
                return String(videoID.prefix(11))
            }
            if let match = url.path.firstMatch(of: watchVideoPattern) {
                return String(match.1)
            }
        }
        return nil
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

    static func embedURL(for videoID: String) -> URL? {
        guard videoID.count == 11 else { return nil }
        return URL(string: "https://www.youtube.com/embed/\(videoID)")
    }

    static func thumbnailURL(for videoID: String) -> URL? {
        guard videoID.count == 11 else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")
    }

    static func shouldKeep(durationSeconds: Int?, minVideoSeconds: Int) -> Bool {
        guard let durationSeconds else { return true }
        return durationSeconds >= minVideoSeconds
    }
}
