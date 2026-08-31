import Foundation

nonisolated enum ContentKind: String, Sendable {
    case article
    case youtube
    case podcast
    case music
}

nonisolated struct ClassifiedEntry: Sendable {
    let kind: ContentKind
    let videoID: String?
    let channelID: String?
    let isShort: Bool
    let durationSeconds: Int?
    let estimatedMinutes: Int
}

nonisolated enum ContentClassifier: Sendable {
    private static let wordsPerMinute = 220
    private static let defaultMinVideoSeconds = 180
    private static let htmlTagPattern = #/<[^>]+>/#

    static func stripHTML(_ html: String) -> String {
        let stripped = html.replacing(htmlTagPattern, with: " ")
        return stripped.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func wordCount(in html: String) -> Int {
        let plain = stripHTML(html)
        guard !plain.isEmpty else { return 0 }
        return plain.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).count
    }

    static func readingMinutes(words: Int) -> Int {
        guard words > 0 else { return 0 }
        return max(1, Int((Double(words) / Double(wordsPerMinute)).rounded()))
    }

    static func consumeMinutes(entryType: ContentKind, words: Int, durationSeconds: Int?) -> Int {
        if entryType == .youtube || entryType == .podcast || entryType == .music,
           let durationSeconds, durationSeconds > 0 {
            return max(1, Int((Double(durationSeconds) / 60.0).rounded()))
        }
        return readingMinutes(words: words)
    }

    static func isYouTubeURL(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be"
    }

    static func inferEntryType(
        url: URL?,
        feedType: ContentKind = .article,
        enclosureMIME: String? = nil
    ) -> ContentKind {
        if feedType == .youtube || feedType == .music || feedType == .podcast {
            return feedType
        }
        if isYouTubeURL(url) { return .youtube }
        let mime = enclosureMIME?.lowercased() ?? ""
        if mime.hasPrefix("audio/") { return .podcast }
        return .article
    }

    static func skipShortYouTube(url: URL?, title: String, durationSeconds: Int?) -> Bool {
        if YouTubeProcessor.isShort(url: url, title: title) { return true }
        if let durationSeconds, durationSeconds < defaultMinVideoSeconds { return true }
        return false
    }

    static func classify(
        url: URL?,
        title: String,
        summary: String?,
        contentHTML: String?,
        enclosureMIME: String?,
        durationSeconds: Int?,
        feedType: ContentKind = .article
    ) -> ClassifiedEntry {
        let kind = inferEntryType(url: url, feedType: feedType, enclosureMIME: enclosureMIME)
        let videoID = kind == .youtube ? YouTubeProcessor.parseVideoID(from: url) : nil
        let channelID = kind == .youtube ? YouTubeProcessor.parseChannelID(from: url) : nil
        let isShort = kind == .youtube && YouTubeProcessor.isShort(url: url, title: title)
        let words = wordCount(in: contentHTML ?? summary ?? "")
        let minutes = consumeMinutes(entryType: kind, words: words, durationSeconds: durationSeconds)
        return ClassifiedEntry(
            kind: kind,
            videoID: videoID,
            channelID: channelID,
            isShort: isShort,
            durationSeconds: durationSeconds,
            estimatedMinutes: minutes
        )
    }
}
