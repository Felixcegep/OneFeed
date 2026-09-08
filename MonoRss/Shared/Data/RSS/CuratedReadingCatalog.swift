import Foundation

/// Cadence subset of `FeedSeedCatalog` (Must read / Builders / À scanner / Papers).
enum CuratedReadingCatalog {
    typealias Entry = FeedSeedCatalog.Entry

    static let folderOrder: [String] = [
        "Must read",
        "Builders",
        "À scanner",
        "Papers",
    ]

    static var feeds: [Entry] {
        let folders = Set(folderOrder)
        return FeedSeedCatalog.feeds.filter { folders.contains($0.folder) }
    }

    static func opmlDocument() -> OPMLDocument {
        var body = ""
        for folderName in folderOrder {
            let items = feeds.filter { $0.folder == folderName }
            guard !items.isEmpty else { continue }
            body += "  <outline text=\"\(escape(folderName))\" title=\"\(escape(folderName))\">\n"
            for entry in items {
                body += "    <outline type=\"rss\" text=\"\(escape(entry.title))\" title=\"\(escape(entry.title))\" xmlUrl=\"\(escape(entry.url.absoluteString))\"/>\n"
            }
            body += "  </outline>\n"
        }
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
        <head>
          <title>OneFeed · AI Reading Pack</title>
          <ownerName>OneFeed</ownerName>
        </head>
        <body>
        \(body.trimmingCharacters(in: .newlines))
        </body>
        </opml>
        """
        return OPMLDocument(data: Data(xml.utf8))
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
