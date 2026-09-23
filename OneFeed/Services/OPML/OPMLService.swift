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

/// Counts for an OPML file before anything is inserted. `outlines` is the parse
/// retained so a later import does not read the file again.
struct OPMLImportPreview: Equatable, Sendable {
    let newSourceCount: Int
    let alreadyPresentCount: Int
    let folderMembershipsToAdd: Int
    let outlines: [OPMLFeedOutline]

    static let confirmationTitle = "Import these sources?"

    var confirmationTitle: String { Self.confirmationTitle }

    /// "12 new sources. 3 already here. 4 folder memberships would be added."
    var confirmationMessage: String {
        let sources = Self.counted(newSourceCount, singular: "new source", plural: "new sources")
        let present = Self.counted(alreadyPresentCount, singular: "already here", plural: "already here")
        let folders = Self.counted(
            folderMembershipsToAdd,
            singular: "folder membership would be added",
            plural: "folder memberships would be added"
        )
        return "\(sources). \(present). \(folders)."
    }

    static func resultTitle(newSourceCount: Int) -> String {
        switch newSourceCount {
        case 0: "No new sources"
        case 1: "Imported 1 source"
        default: "Imported \(newSourceCount) sources"
        }
    }

    static func resultMessage(folderMembershipsAdded: Int, refreshError: String?) -> String {
        var lines: [String] = []
        switch folderMembershipsAdded {
        case 0: break
        case 1: lines.append("Added 1 folder membership.")
        default: lines.append("Added \(folderMembershipsAdded) folder memberships.")
        }
        if let refreshError, refreshError.isEmpty == false {
            lines.append(refreshError)
        }
        return lines.joined(separator: "\n")
    }

    private static func counted(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}

@MainActor
struct OPMLService {
    /// Reads the document and reports what import would change. Does not insert.
    func previewDocument(_ data: Data, in context: ModelContext) throws -> OPMLImportPreview {
        let outlines = try Self.parse(data)
        let feeds = try context.fetch(FetchDescriptor<Feed>())
        var known: [(url: URL, folders: Set<String>)] = feeds.map { feed in
            (feed.feedURL, Set(feed.memberships.map { $0.lowercased() }))
        }
        var newSourceCount = 0
        var alreadyPresentCount = 0
        var folderMembershipsToAdd = 0
        var countedURLs = Set<URL>()

        for outline in outlines {
            let feedURL = outline.feedURL
            if countedURLs.insert(feedURL).inserted {
                if known.contains(where: { $0.url == feedURL }) {
                    alreadyPresentCount += 1
                } else {
                    newSourceCount += 1
                    known.append((feedURL, []))
                }
            }
            guard let folder = FeedMembership.normalized(outline.folderName)?.lowercased() else { continue }
            guard let index = known.firstIndex(where: { $0.url == feedURL }) else { continue }
            var entry = known[index]
            if entry.folders.insert(folder).inserted {
                folderMembershipsToAdd += 1
                known[index] = entry
            }
        }

        return OPMLImportPreview(
            newSourceCount: newSourceCount,
            alreadyPresentCount: alreadyPresentCount,
            folderMembershipsToAdd: folderMembershipsToAdd,
            outlines: outlines
        )
    }

    func importDocument(_ data: Data, in context: ModelContext) throws -> Int {
        try importOutlines(try Self.parse(data), in: context).newSources
    }

    /// Insert path shared by a fresh parse and by a preview already held in memory.
    func importOutlines(_ outlines: [OPMLFeedOutline], in context: ModelContext) throws -> (newSources: Int, folderMembershipsAdded: Int) {
        var inserted = 0
        var memberships = 0
        for outline in outlines {
            let feedURL = outline.feedURL
            let descriptor = FetchDescriptor<Feed>(predicate: #Predicate { $0.feedURL == feedURL })
            if let existing = try context.fetch(descriptor).first {
                if let folder = outline.folderName, existing.addFolder(folder) {
                    memberships += 1
                }
                continue
            }
            context.insert(Feed(
                title: outline.title,
                feedURL: feedURL,
                folderName: outline.folderName
            ))
            inserted += 1
            if FeedMembership.normalized(outline.folderName) != nil {
                memberships += 1
            }
        }
        try context.save()
        return (inserted, memberships)
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
            let title = attributeDict.first(where: { $0.key.caseInsensitiveCompare("title") == .orderedSame })?.value
                ?? attributeDict.first(where: { $0.key.caseInsensitiveCompare("text") == .orderedSame })?.value
                ?? feedURL.host()
                ?? "Imported Source"
            let folder = currentFolder
            if seenURLs.insert(key).inserted {
                outlines.append(OPMLFeedOutline(title: title, feedURL: feedURL, folderName: folder))
            } else if let folder, !folder.isEmpty {
                outlines.append(OPMLFeedOutline(title: title, feedURL: feedURL, folderName: folder))
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
