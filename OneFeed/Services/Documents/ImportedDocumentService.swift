import Foundation
import PDFKit
import SwiftData

nonisolated struct PreparedImport: Sendable {
    var kind: ImportedDocumentKind
    var hash: String
    var fileURL: URL
    var sourceURL: URL?
    var title: String
    var author: String?
    var html: String?
    var summary: String?
    var minutes: Int
}

@MainActor
struct ImportedDocumentService {
    static let maxImportBytes = 200 * 1_024 * 1_024
    static let persistedHTMLLimit = 1_500_000

    var store: ImportedDocumentStore
    var session: URLSession

    init(store: ImportedDocumentStore = .shared, session: URLSession = .shared) {
        self.store = store
        self.session = session
    }

    @discardableResult
    func importFile(at url: URL, in context: ModelContext) async throws -> Article {
        let store = self.store
        let prepared = try await Task.detached {
            try Self.prepare(from: url, store: store, sourceURL: url.isFileURL ? nil : url)
        }.value
        return try upsert(prepared, in: context)
    }

    @discardableResult
    func importRemote(url: URL, in context: ModelContext) async throws -> Article {
        var request = URLRequest(url: url)
        request.setValue("OneFeed/1.0", forHTTPHeaderField: "User-Agent")
        let (temp, response) = try await session.download(for: request)
        var cleanup = temp
        defer { try? FileManager.default.removeItem(at: cleanup) }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ImportedDocumentError.downloadFailed
        }
        if let length = http.value(forHTTPHeaderField: "Content-Length"),
           let bytes = Int(length), bytes > Self.maxImportBytes {
            throw ImportedDocumentError.tooLarge
        }
        let mime = http.value(forHTTPHeaderField: "Content-Type") ?? response.mimeType
        var kind = ImportedDocumentKind.infer(url: url, mime: mime)
        if kind == nil {
            let prefix = try Data(contentsOf: temp).prefix(8)
            kind = ImportedDocumentKind.infer(magic: Data(prefix))
        }
        guard let kind else { throw ImportedDocumentError.unsupportedType }

        let named = temp.deletingLastPathComponent().appending(path: "download.\(kind.fileExtension)")
        try? FileManager.default.removeItem(at: named)
        try FileManager.default.moveItem(at: temp, to: named)
        cleanup = named

        let store = self.store
        let prepared = try await Task.detached {
            try Self.prepare(from: named, store: store, sourceURL: url)
        }.value
        return try upsert(prepared, in: context)
    }

    nonisolated static func prepare(
        from url: URL,
        store: ImportedDocumentStore,
        sourceURL: URL?
    ) throws -> PreparedImport {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxImportBytes {
            throw ImportedDocumentError.tooLarge
        }

        var kind = ImportedDocumentKind.infer(url: url)
        if kind == nil {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let prefix = try handle.read(upToCount: 8) ?? Data()
            kind = ImportedDocumentKind.infer(magic: prefix)
        }
        guard let kind else { throw ImportedDocumentError.unsupportedType }

        let hash = try CloudFileContentHash.sha256Hex(ofFile: url)
        let stored = try store.copy(url, hash: hash, kind: kind)
        let filenameTitle = title(fromFileName: url.lastPathComponent)

        switch kind {
        case .pdf:
            let info = try pdfInfo(from: stored)
            return PreparedImport(
                kind: kind,
                hash: hash,
                fileURL: stored,
                sourceURL: httpURL(sourceURL),
                title: info.title ?? filenameTitle,
                author: info.author,
                html: nil,
                summary: info.summary,
                minutes: max(1, info.pages)
            )
        case .epub:
            let book = try EPUBReader.load(epub: stored, extractedTo: store.extractedDirectory(hash: hash))
            let html = book.html.utf8.count <= persistedHTMLLimit ? book.html : nil
            return PreparedImport(
                kind: kind,
                hash: hash,
                fileURL: stored,
                sourceURL: httpURL(sourceURL),
                title: book.title.isEmpty ? filenameTitle : book.title,
                author: book.author,
                html: html,
                summary: ContentClassifier.plainExcerpt(book.html),
                minutes: max(1, ContentClassifier.readingMinutes(words: book.wordCount))
            )
        }
    }

    private func upsert(_ prepared: PreparedImport, in context: ModelContext) throws -> Article {
        let guid = prepared.kind.guid(hash: prepared.hash)
        if let existing = existing(guid: guid, in: context) {
            if existing.enclosureURL == nil {
                existing.enclosureURL = prepared.fileURL
                existing.enclosureMIME = prepared.kind.mimeType
            }
            try QueueLinkService().park(existing, in: context)
            return existing
        }
        if let source = prepared.sourceURL, let existing = existing(url: source, in: context) {
            try QueueLinkService().park(existing, in: context)
            return existing
        }

        let article = Article(
            guid: guid,
            title: prepared.title,
            url: prepared.sourceURL ?? prepared.kind.identityURL(hash: prepared.hash),
            author: prepared.author,
            publishedAt: .now,
            summary: prepared.summary,
            contentHTML: prepared.html,
            estimatedReadingMinutes: prepared.minutes,
            state: .saved,
            isRemoteStarred: true,
            contentKind: prepared.kind.rawValue,
            enclosureURL: prepared.fileURL,
            enclosureMIME: prepared.kind.mimeType,
            libraryUpdatedAt: .now
        )
        article.completedAt = .now
        context.insert(article)
        LibraryChange.note(article)
        try context.save()
        return article
    }

    private func existing(guid: String, in context: ModelContext) -> Article? {
        var descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.guid == guid })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func existing(url: URL, in context: ModelContext) -> Article? {
        let key = ArticleIdentity.normalizedURLString(url)
        let articles = (try? context.fetch(FetchDescriptor<Article>())) ?? []
        return articles.first { ArticleIdentity.normalizedURLString($0.url) == key }
    }

    private nonisolated static func httpURL(_ url: URL?) -> URL? {
        let scheme = url?.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    private nonisolated static func title(fromFileName name: String) -> String {
        let stem = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        let cleaned = stem
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? name : cleaned
    }

    private nonisolated static func pdfInfo(from url: URL) throws -> (title: String?, author: String?, pages: Int, summary: String?) {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            throw ImportedDocumentError.invalidPDF
        }
        let attributes = document.documentAttributes ?? [:]
        let metadataTitle = trimmed(attributes[PDFDocumentAttribute.titleAttribute] as? String)
        let metadataAuthor = trimmed(attributes[PDFDocumentAttribute.authorAttribute] as? String)
        let heading = pdfHeading(from: document.page(at: 0)?.string ?? "")
        let title = metadataTitle ?? heading.title
        let author = metadataAuthor ?? heading.author
        return (title, author, document.pageCount, heading.summary)
    }

    /// Papers such as PVLDB often leave the title out of the PDF metadata and put it on the first page.
    nonisolated static func pdfHeading(from pageText: String) -> (title: String?, author: String?, summary: String?) {
        let lines = pageText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let titleIndex = lines.firstIndex(where: isPaperTitleLine) else {
            return (nil, nil, abstract(in: pageText))
        }
        var authors: [String] = []
        for line in lines.dropFirst(titleIndex + 1) {
            if line.uppercased().hasPrefix("ABSTRACT") { break }
            if isAuthorName(line) { authors.append(line) }
            if authors.count == 6 { break }
        }
        let author = authors.isEmpty ? nil : authors.joined(separator: ", ")
        return (lines[titleIndex], author, abstract(in: pageText))
    }

    private nonisolated static func isPaperTitleLine(_ line: String) -> Bool {
        guard (12...200).contains(line.count), line.contains(where: \.isLetter), !line.contains("@") else { return false }
        if line.uppercased().hasPrefix("ABSTRACT") || line.uppercased().hasPrefix("INTRODUCTION") { return false }
        return true
    }

    private nonisolated static func isAuthorName(_ line: String) -> Bool {
        guard !line.contains("@"), (3...48).contains(line.count) else { return false }
        let words = line.split(separator: " ")
        guard (2...4).contains(words.count) else { return false }
        return words.allSatisfy { word in
            guard let first = word.first, first.isUppercase else { return false }
            return word.allSatisfy { $0.isLetter || $0 == "-" || $0 == "." || $0 == "'" }
        }
    }

    private nonisolated static func abstract(in text: String) -> String? {
        guard let marker = text.range(of: "ABSTRACT", options: .caseInsensitive) else { return nil }
        var body = String(text[marker.upperBound...])
        if let intro = body.range(of: "INTRODUCTION", options: .caseInsensitive) {
            body = String(body[..<intro.lowerBound])
        }
        let plain = ContentClassifier.plainExcerpt(body, maxCharacters: 280)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return plain.isEmpty ? nil : plain
    }

    private nonisolated static func trimmed(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }
}
