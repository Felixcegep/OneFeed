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

@MainActor
struct OPMLService {
    func importDocument(_ data: Data, in context: ModelContext) throws -> Int {
        guard let xml = String(data: data, encoding: .utf8) else { throw OPMLServiceError.invalidDocument }
        let pattern = #"<outline\b[^>]*\bxmlUrl=[\"']([^\"']+)[\"'][^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return 0 }
        var inserted = 0
        let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
        for match in matches {
            guard let urlRange = Range(match.range(at: 1), in: xml), let feedURL = URL(string: String(xml[urlRange])) else { continue }
            let fullRange = Range(match.range(at: 0), in: xml).map { String(xml[$0]) } ?? ""
            let title = Self.attribute("title", in: fullRange) ?? Self.attribute("text", in: fullRange) ?? feedURL.host() ?? "Imported Source"
            let remoteID: String? = nil
            let descriptor = FetchDescriptor<Feed>(predicate: #Predicate { $0.feedURL == feedURL })
            if try context.fetch(descriptor).isEmpty {
                context.insert(Feed(title: title, feedURL: feedURL, remoteID: remoteID))
                inserted += 1
            }
        }
        try context.save()
        return inserted
    }

    func exportDocument(feeds: [Feed]) -> OPMLDocument {
        let outlines = feeds.map {
            "    <outline type=\"rss\" text=\"\(Self.escape($0.title))\" title=\"\(Self.escape($0.title))\" xmlUrl=\"\(Self.escape($0.feedURL.absoluteString))\"/>"
        }.joined(separator: "\n")
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0"><head><title>OneFeed Sources</title></head><body>
        \(outlines)
        </body></opml>
        """
        return OPMLDocument(data: Data(xml.utf8))
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\b\(name)=[\\\"']([^\\\"']+)[\\\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              let range = Range(match.range(at: 1), in: tag) else { return nil }
        return String(tag[range])
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

enum OPMLServiceError: LocalizedError {
    case invalidDocument
    var errorDescription: String? { "That file is not a valid OPML document." }
}
