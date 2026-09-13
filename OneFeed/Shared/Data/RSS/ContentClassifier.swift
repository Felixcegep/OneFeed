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
        var stripped = html.replacing(htmlTagPattern, with: " ")
        stripped = stripped.replacing(/<\/?[a-zA-Z][^>]*>?/, with: " ")
        stripped = decodeEntities(stripped)
        return stripped.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func plainExcerpt(_ html: String, maxCharacters: Int = 220) -> String {
        let plain = stripHTML(html)
        guard plain.count > maxCharacters else { return plain }
        let limit = plain.index(plain.startIndex, offsetBy: maxCharacters)
        if let space = plain[..<limit].lastIndex(of: " ") {
            return String(plain[..<space]) + "…"
        }
        return String(plain[..<limit]) + "…"
    }

    private static let namedEntities: [(String, String)] = [
        ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
        ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
        ("&mdash;", "—"), ("&ndash;", "–"), ("&hellip;", "…"),
        ("&rsquo;", "’"), ("&lsquo;", "‘"), ("&rdquo;", "”"), ("&ldquo;", "“")
    ]

    private static func decodeEntities(_ string: String) -> String {
        var result = string
        for (entity, value) in namedEntities {
            result = result.replacingOccurrences(of: entity, with: value, options: .caseInsensitive)
        }
        return decodeNumericEntities(result)
    }

    private static func decodeNumericEntities(_ string: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "&#(x)?([0-9a-fA-F]+);", options: [.caseInsensitive]) else {
            return string
        }
        let matches = regex.matches(in: string, range: NSRange(string.startIndex..., in: string))
        var result = string
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let valueRange = Range(match.range(at: 2), in: result) else { continue }
            let isHex = match.range(at: 1).location != NSNotFound
            let raw = String(result[valueRange])
            let value = isHex ? UInt32(raw, radix: 16) : UInt32(raw)
            guard let value, value >= 32, let scalar = Unicode.Scalar(value) else { continue }
            result.replaceSubrange(fullRange, with: String(Character(scalar)))
        }
        return result
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
