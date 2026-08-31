import Foundation

nonisolated struct ParsedFeed: Sendable {
    let title: String
    let websiteURL: URL?
    let articles: [ParsedArticle]
}

nonisolated struct ParsedArticle: Sendable {
    let guid: String
    let title: String
    let url: URL?
    let author: String?
    let publishedAt: Date
    let summary: String?
    let contentHTML: String?
    let enclosureURL: URL?
    let enclosureMIME: String?
    let durationSeconds: Int?
    let imageURL: URL?
    let updatedAt: Date?

    init(
        guid: String,
        title: String,
        url: URL?,
        author: String?,
        publishedAt: Date,
        summary: String?,
        contentHTML: String?,
        enclosureURL: URL? = nil,
        enclosureMIME: String? = nil,
        durationSeconds: Int? = nil,
        imageURL: URL? = nil,
        updatedAt: Date? = nil
    ) {
        self.guid = guid
        self.title = title
        self.url = url
        self.author = author
        self.publishedAt = publishedAt
        self.summary = summary
        self.contentHTML = contentHTML
        self.enclosureURL = enclosureURL
        self.enclosureMIME = enclosureMIME
        self.durationSeconds = durationSeconds
        self.imageURL = imageURL
        self.updatedAt = updatedAt
    }

    var estimatedReadingMinutes: Int {
        let source = contentHTML ?? summary ?? ""
        let plain = source.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let words = plain.split(whereSeparator: \.isWhitespace).count
        return max(1, Int(ceil(Double(words) / 220.0)))
    }
}

nonisolated enum FeedParserError: LocalizedError {
    case invalidXML(String)
    case noFeed

    var errorDescription: String? {
        switch self {
        case .invalidXML(let message): "The source returned an invalid feed: \(message)"
        case .noFeed: "No RSS or Atom feed was found at this address."
        }
    }
}

nonisolated struct FeedParser: Sendable {
    func parse(_ data: Data) throws -> ParsedFeed {
        let delegate = XMLFeedDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        guard parser.parse() else {
            throw FeedParserError.invalidXML(parser.parserError?.localizedDescription ?? "Unknown XML error")
        }
        guard !delegate.articles.isEmpty || delegate.feedTitle != nil else {
            throw FeedParserError.noFeed
        }
        return ParsedFeed(
            title: delegate.feedTitle?.trimmed.nonEmpty ?? "Untitled Source",
            websiteURL: delegate.websiteURL,
            articles: delegate.articles
        )
    }
}

nonisolated private final class XMLFeedDelegate: NSObject, XMLParserDelegate {
    var feedTitle: String?
    var websiteURL: URL?
    var articles: [ParsedArticle] = []

    private var elementStack: [String] = []
    private var text = ""
    private var inEntry = false
    private var values: [String: String] = [:]
    private var entryURL: URL?
    private var feedLinkCandidate: URL?
    private var enclosureURL: URL?
    private var enclosureMIME: String?
    private var durationSeconds: Int?
    private var imageURL: URL?
    private var updatedAt: Date?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = (qName ?? elementName).lowercased()
        elementStack.append(name)
        text = ""
        if name == "item" || name == "entry" {
            inEntry = true
            values = [:]
            entryURL = nil
            enclosureURL = nil
            enclosureMIME = nil
            durationSeconds = nil
            imageURL = nil
            updatedAt = nil
        }
        if name == "enclosure", inEntry,
           let urlString = attributeDict["url"], let url = URL(string: urlString) {
            enclosureURL = url
            enclosureMIME = attributeDict["type"]
        }
        if name == "link", let href = attributeDict["href"], let url = URL(string: href) {
            let rel = attributeDict["rel"] ?? "alternate"
            if inEntry {
                if rel == "alternate" { entryURL = url }
                if rel == "enclosure" {
                    enclosureURL = url
                    enclosureMIME = attributeDict["type"]
                }
            } else if rel == "alternate" {
                feedLinkCandidate = url
            }
        }
        if inEntry {
            if name == "media:thumbnail", let urlString = attributeDict["url"] ?? attributeDict["href"] {
                imageURL = imageURL ?? URL(string: urlString)
            }
            if name == "itunes:image", let urlString = attributeDict["href"] {
                imageURL = imageURL ?? URL(string: urlString)
            }
            if name == "media:content", let duration = attributeDict["duration"] {
                durationSeconds = durationSeconds ?? Self.parseDurationText(duration)
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = (qName ?? elementName).lowercased()
        let value = text.trimmed

        if inEntry {
            if !value.isEmpty { values[name] = (values[name] ?? "") + value }
            if name == "link", entryURL == nil, let url = URL(string: value) { entryURL = url }
            if name == "itunes:duration" {
                durationSeconds = durationSeconds ?? Self.parseDurationText(value)
            }
            if name == "updated" || name == "dc:date" {
                updatedAt = updatedAt ?? Self.parseDate(value)
            }
            if name == "item" || name == "entry" {
                appendEntry()
                inEntry = false
            }
        } else {
            if name == "title", feedTitle == nil, !value.isEmpty { feedTitle = value }
            if name == "link", let url = URL(string: value) { websiteURL = url }
        }

        if name == "rss" || name == "feed" { websiteURL = websiteURL ?? feedLinkCandidate }
        _ = elementStack.popLast()
        text = ""
    }

    private func appendEntry() {
        let title = values["title"]?.trimmed.nonEmpty ?? "Untitled article"
        let guid = values["guid"] ?? values["id"] ?? entryURL?.absoluteString ?? title
        let dateText = values["pubdate"] ?? values["published"] ?? values["updated"]
        let date = dateText.flatMap(Self.parseDate) ?? .now
        let content = values["content:encoded"] ?? values["encoded"] ?? values["content"]
        let summary = values["description"] ?? values["summary"]
        let resolvedImage = imageURL
            ?? values["image"].flatMap { URL(string: $0.trimmed) }
            ?? Self.firstImageURL(in: content ?? summary ?? "")
        let article = ParsedArticle(
            guid: guid,
            title: title,
            url: entryURL,
            author: values["dc:creator"] ?? values["creator"] ?? values["author"] ?? values["name"],
            publishedAt: date,
            summary: summary,
            contentHTML: content,
            enclosureURL: enclosureURL,
            enclosureMIME: enclosureMIME,
            durationSeconds: durationSeconds,
            imageURL: resolvedImage,
            updatedAt: updatedAt ?? dateText.flatMap(Self.parseDate)
        )
        articles.append(article)
    }

    private static func parseDurationText(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let seconds = Int(trimmed) { return seconds }
        let parts = trimmed.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 2: return parts[0] * 60 + parts[1]
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default: return nil
        }
    }

    private static func firstImageURL(in html: String) -> URL? {
        let pattern = #/<img[^>]+src=["']([^"']+)["']/#
        guard let match = html.firstMatch(of: pattern) else { return nil }
        return URL(string: String(match.1))
    }

    private static func parseDate(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "dd MMM yyyy HH:mm:ss Z", "yyyy-MM-dd'T'HH:mm:ssZ"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

nonisolated private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? { isEmpty ? nil : self }
}
