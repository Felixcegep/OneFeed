import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct OPMLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.xml, UTType(filenameExtension: "opml") ?? .xml] }
    var data: Data

    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct OPMLFeedOutline: Equatable, Sendable {
    let title: String
    let feedURL: URL
    let folderName: String?
}

@MainActor
struct OPMLService {
    func importDocument(_ data: Data, in context: ModelContext) throws -> Int {
        let outlines = try Self.parse(data)
        var inserted = 0
        for outline in outlines {
            let feedURL = outline.feedURL
            let descriptor = FetchDescriptor<Feed>(predicate: #Predicate { $0.feedURL == feedURL })
            if let existing = try context.fetch(descriptor).first {
                if let folder = outline.folderName, existing.folderName != folder {
                    existing.folderName = folder
                }
                continue
            }
            context.insert(Feed(
                title: outline.title,
                feedURL: feedURL,
                folderName: outline.folderName
            ))
            inserted += 1
        }
        try context.save()
        return inserted
    }

    func exportDocument(feeds: [Feed]) -> OPMLDocument {
        let groups = FeedFolderGrouping.groups(from: feeds)
        var body = ""
        for group in groups {
            switch group.folderID {
            case .named(let name):
                body += "  <outline text=\"\(Self.escape(name))\" title=\"\(Self.escape(name))\">\n"
                for feed in group.feeds {
                    body += "    \(Self.feedOutline(feed))\n"
                }
                body += "  </outline>\n"
            case .unfiled:
                for feed in group.feeds {
                    body += "  \(Self.feedOutline(feed))\n"
                }
            }
        }
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
        <head><title>OneFeed Sources</title></head>
        <body>
        \(body.trimmingCharacters(in: .newlines))
        </body>
        </opml>
        """
        return OPMLDocument(data: Data(xml.utf8))
    }

    static func parse(_ data: Data) throws -> [OPMLFeedOutline] {
        let parser = OPMLOutlineParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse() else { throw OPMLServiceError.invalidDocument }
        return parser.outlines
    }

    private static func feedOutline(_ feed: Feed) -> String {
        "<outline type=\"rss\" text=\"\(escape(feed.title))\" title=\"\(escape(feed.title))\" xmlUrl=\"\(escape(feed.feedURL.absoluteString))\"/>"
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

enum OPMLServiceError: LocalizedError {
    case invalidDocument
    var errorDescription: String? { "That file is not a valid OPML document." }
}

private final class OPMLOutlineParser: NSObject, XMLParserDelegate {
    private enum Frame {
        case folder(String)
        case feed
    }

    private(set) var outlines: [OPMLFeedOutline] = []
    private var stack: [Frame] = []
    private var seenURLs = Set<String>()

    private var currentFolder: String? {
        for frame in stack.reversed() {
            if case .folder(let name) = frame, !name.isEmpty { return name }
        }
        return nil
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName.caseInsensitiveCompare("outline") == .orderedSame else { return }
        let xmlURL = attributeDict.first(where: { $0.key.caseInsensitiveCompare("xmlUrl") == .orderedSame })?.value
            ?? attributeDict.first(where: { $0.key.caseInsensitiveCompare("xmlurl") == .orderedSame })?.value

        if let rawURL = xmlURL, let feedURL = URL(string: rawURL) {
            let key = feedURL.absoluteString
            if seenURLs.insert(key).inserted {
                let title = attributeDict.first(where: { $0.key.caseInsensitiveCompare("title") == .orderedSame })?.value
                    ?? attributeDict.first(where: { $0.key.caseInsensitiveCompare("text") == .orderedSame })?.value
                    ?? feedURL.host()
                    ?? "Imported Source"
                outlines.append(OPMLFeedOutline(title: title, feedURL: feedURL, folderName: currentFolder))
            }
            stack.append(.feed)
            return
        }

        let name = attributeDict.first(where: { $0.key.caseInsensitiveCompare("text") == .orderedSame })?.value
            ?? attributeDict.first(where: { $0.key.caseInsensitiveCompare("title") == .orderedSame })?.value
            ?? ""
        stack.append(.folder(name.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName.caseInsensitiveCompare("outline") == .orderedSame, !stack.isEmpty else { return }
        stack.removeLast()
    }
}
