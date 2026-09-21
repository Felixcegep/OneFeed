import Foundation

nonisolated struct EPUBDocument: Sendable {
    var title: String
    var author: String?
    var html: String
    var wordCount: Int
}

nonisolated enum EPUBReader {
    static func load(epub url: URL, extractedTo directory: URL) throws -> EPUBDocument {
        if FileManager.default.fileExists(atPath: directory.appending(path: "META-INF/encryption.xml").path) {
            throw ImportedDocumentError.locked
        }
        if !FileManager.default.fileExists(atPath: directory.appending(path: "META-INF/container.xml").path) {
            try ZipArchive.extractAll(from: url, to: directory)
        }
        if FileManager.default.fileExists(atPath: directory.appending(path: "META-INF/encryption.xml").path) {
            throw ImportedDocumentError.locked
        }
        return try load(extracted: directory)
    }

    static func load(extracted directory: URL) throws -> EPUBDocument {
        let containerURL = directory.appending(path: "META-INF/container.xml")
        guard let container = try? String(contentsOf: containerURL, encoding: .utf8),
              let opfRelative = EPUBXML.firstAttribute("full-path", in: container) else {
            throw ImportedDocumentError.invalidEPUB
        }
        let opfURL = directory.appending(path: opfRelative)
        guard let opf = try? String(contentsOf: opfURL, encoding: .utf8) else {
            throw ImportedDocumentError.invalidEPUB
        }

        let title = EPUBXML.element("title", in: opf)?.decodedXML
            ?? directory.deletingLastPathComponent().lastPathComponent
        let author = EPUBXML.element("creator", in: opf)?.decodedXML

        var hrefByID: [String: String] = [:]
        var typeByID: [String: String] = [:]
        for tag in EPUBXML.openingTags("item", in: opf) {
            guard let id = EPUBXML.attribute("id", in: tag),
                  let href = EPUBXML.attribute("href", in: tag) else { continue }
            hrefByID[id] = href
            if let type = EPUBXML.attribute("media-type", in: tag) {
                typeByID[id] = type.lowercased()
            }
        }

        let opfDirectory = opfURL.deletingLastPathComponent()
        var chapters: [String] = []
        for tag in EPUBXML.openingTags("itemref", in: opf) {
            if EPUBXML.attribute("linear", in: tag)?.lowercased() == "no" { continue }
            guard let idref = EPUBXML.attribute("idref", in: tag),
                  let href = hrefByID[idref] else { continue }
            let media = typeByID[idref] ?? ""
            if !media.isEmpty,
               !media.contains("html"),
               media != "application/xhtml+xml",
               media != "text/html" {
                continue
            }
            let chapterURL = URL(fileURLWithPath: href, relativeTo: opfDirectory).standardizedFileURL
            let xhtml = (try? String(contentsOf: chapterURL, encoding: .utf8))
                ?? (try? Data(contentsOf: chapterURL)).flatMap { String(data: $0, encoding: .utf8) }
            guard let xhtml else { continue }
            let chapterPath = chapterURL.path
            let body = rewriteResources(in: bodyHTML(from: xhtml), chapterPath: chapterPath, opfDirectory: opfDirectory.path)
            if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chapters.append("<section>\(body)</section>")
            }
        }
        guard !chapters.isEmpty else { throw ImportedDocumentError.invalidEPUB }
        let html = chapters.joined(separator: "\n")
        return EPUBDocument(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            author: author?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
            html: html,
            wordCount: ContentClassifier.wordCount(in: html)
        )
    }

    static func opfDirectory(in extracted: URL) -> URL? {
        let containerURL = extracted.appending(path: "META-INF/container.xml")
        guard let container = try? String(contentsOf: containerURL, encoding: .utf8),
              let opfRelative = EPUBXML.firstAttribute("full-path", in: container) else {
            return nil
        }
        return extracted.appending(path: opfRelative).deletingLastPathComponent()
    }

    static func html(fromEPUB url: URL, extractedTo directory: URL) throws -> String {
        try load(epub: url, extractedTo: directory).html
    }

    private static func bodyHTML(from xhtml: String) -> String {
        guard let bodyRange = xhtml.range(of: "<body", options: .caseInsensitive),
              let start = xhtml[bodyRange.lowerBound...].range(of: ">"),
              let end = xhtml.range(of: "</body>", options: [.caseInsensitive, .backwards]) else {
            return xhtml
        }
        return String(xhtml[start.upperBound..<end.lowerBound])
    }

    private static func rewriteResources(in html: String, chapterPath: String, opfDirectory: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(\bsrc\s*=\s*|xlink:href\s*=\s*)(["'])([^"']+)\2"#, options: [.caseInsensitive]) else {
            return html
        }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var result = html
        for match in matches.reversed() {
            guard match.numberOfRanges > 3,
                  let valueRange = Range(match.range(at: 3), in: result) else { continue }
            let value = String(result[valueRange])
            let rewritten = resolved(value, chapterPath: chapterPath, opfDirectory: opfDirectory)
            result.replaceSubrange(valueRange, with: rewritten)
        }
        return result
    }

    private static func resolved(_ relative: String, chapterPath: String, opfDirectory: String) -> String {
        let trimmed = relative.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if trimmed.isEmpty
            || trimmed.hasPrefix("#")
            || lower.hasPrefix("http://")
            || lower.hasPrefix("https://")
            || lower.hasPrefix("data:")
            || lower.hasPrefix("mailto:") {
            return trimmed
        }
        let chapterDir = URL(fileURLWithPath: chapterPath).deletingLastPathComponent()
        let absolute = URL(fileURLWithPath: trimmed, relativeTo: chapterDir).standardizedFileURL
        let base = URL(fileURLWithPath: opfDirectory, isDirectory: true).standardizedFileURL
        let path = absolute.path
        let root = base.path
        guard path.hasPrefix(root) else { return trimmed }
        var rest = String(path.dropFirst(root.count))
        if rest.hasPrefix("/") { rest.removeFirst() }
        return rest
    }
}

nonisolated enum EPUBXML {
    static func firstAttribute(_ name: String, in xml: String) -> String? {
        attribute(name, in: xml)
    }

    static func element(_ localName: String, in xml: String) -> String? {
        let pattern = "<(?:[A-Za-z0-9_]+:)?\(NSRegularExpression.escapedPattern(for: localName))(?:\\s[^>]*)?>([\\s\\S]*?)</(?:[A-Za-z0-9_]+:)?\(NSRegularExpression.escapedPattern(for: localName))\\s*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        return String(xml[range])
    }

    static func openingTags(_ localName: String, in xml: String) -> [String] {
        let pattern = "<(?:[A-Za-z0-9_]+:)?\(NSRegularExpression.escapedPattern(for: localName))\\b[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).compactMap { match in
            Range(match.range, in: xml).map { String(xml[$0]) }
        }
    }

    static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*(\"([^\"]*)\"|'([^']*)')"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else {
            return nil
        }
        if match.numberOfRanges > 2, let range = Range(match.range(at: 2), in: tag), !range.isEmpty {
            return String(tag[range])
        }
        if match.numberOfRanges > 3, let range = Range(match.range(at: 3), in: tag) {
            return String(tag[range])
        }
        return nil
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }

    var decodedXML: String {
        ContentClassifier.stripHTML(self)
    }
}
