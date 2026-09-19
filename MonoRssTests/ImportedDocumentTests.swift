import Foundation
import PDFKit
import SwiftData
import Testing
@testable import OneFeed

@MainActor
struct ImportedDocumentTests {
    @Test func infersPDFAndEPUBFromURLAndMagic() {
        #expect(ImportedDocumentKind.infer(url: URL(fileURLWithPath: "/tmp/paper.pdf")) == .pdf)
        #expect(ImportedDocumentKind.infer(url: URL(fileURLWithPath: "/tmp/book.epub")) == .epub)
        #expect(ImportedDocumentKind.infer(url: URL(string: "https://arxiv.org/pdf/2401.00001.pdf")!) == .pdf)
        #expect(ImportedDocumentKind.infer(url: URL(string: "https://example.com/story")!) == nil)
        #expect(ImportedDocumentKind.infer(magic: Data("%PDF-1.4".utf8)) == .pdf)
        #expect(ImportedDocumentKind.infer(magic: Data("PK\u{3}\u{4}".utf8)) == nil)
        #expect(ImportedDocumentKind.infer(url: URL(string: "https://example.com/a")!, mime: "application/pdf") == .pdf)
        #expect(ImportedDocumentKind.infer(url: URL(string: "https://example.com/a")!, mime: "application/epub+zip") == .epub)
    }

    @Test func importingAPDFParksItInTheQueue() async throws {
        let context = try InMemoryStore.makeContext()
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let pdf = try writePDF(title: "Attention Is All You Need", to: root.appending(path: "paper.pdf"))

        let article = try await ImportedDocumentService(store: ImportedDocumentStore(rootURL: root))
            .importFile(at: pdf, in: context)

        #expect(article.state == .saved)
        #expect(article.contentKind == "pdf")
        #expect(article.title == "Attention Is All You Need")
        #expect(article.kindLabel == "PDF")
        #expect(article.isImportedDocument)
        #expect(article.guid.hasPrefix("imported:pdf:"))
        #expect(ImportedDocumentStore.hash(fromGuid: article.guid) != nil)
        #expect(FileManager.default.fileExists(atPath: article.enclosureURL!.path))
        #expect(ArticlePresentation.sourceName(for: article) == "PDF")
    }

    @Test func importingTheSameFileAgainParksTheExistingArticle() async throws {
        let context = try InMemoryStore.makeContext()
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let pdf = try writePDF(title: "Same Paper", to: root.appending(path: "same.pdf"))
        let service = ImportedDocumentService(store: ImportedDocumentStore(rootURL: root))

        let first = try await service.importFile(at: pdf, in: context)
        first.state = .read
        try context.save()
        let second = try await service.importFile(at: pdf, in: context)

        #expect(second.id == first.id)
        #expect(first.state == .saved)
        #expect(try context.fetchCount(FetchDescriptor<Article>()) == 1)
    }

    @Test func importingAnEPUBExtractsTitleAuthorAndReadableHTML() async throws {
        let context = try InMemoryStore.makeContext()
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let epub = try writeEPUB(
            title: "Test Book",
            author: "Ada Lovelace",
            body: "<p>Machines can compose as well as calculate.</p>",
            to: root.appending(path: "book.epub")
        )

        let article = try await ImportedDocumentService(store: ImportedDocumentStore(rootURL: root))
            .importFile(at: epub, in: context)

        #expect(article.contentKind == "epub")
        #expect(article.title == "Test Book")
        #expect(article.author == "Ada Lovelace")
        #expect(article.contentHTML?.contains("Machines can compose") == true)
        #expect(ArticlePresentation.sourceName(for: article) == "Ada Lovelace")
        #expect(article.kindLabel == "Book")
    }

    @Test func lockedEPUBIsRejected() async throws {
        let context = try InMemoryStore.makeContext()
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let epub = try writeEPUB(
            title: "Locked",
            author: nil,
            body: "<p>Secret</p>",
            to: root.appending(path: "locked.epub"),
            encrypted: true
        )

        await #expect(throws: ImportedDocumentError.locked) {
            _ = try await ImportedDocumentService(store: ImportedDocumentStore(rootURL: root))
                .importFile(at: epub, in: context)
        }
    }

    @Test func zipReaderExtractsStoredEntriesAndRejectsSlip() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let archiveURL = root.appending(path: "files.zip")
        try ZipArchive.storedArchive(entries: [
            ("folder/note.txt", Data("hello zip".utf8))
        ]).write(to: archiveURL)
        let extracted = root.appending(path: "out", directoryHint: .isDirectory)
        try ZipArchive.extractAll(from: archiveURL, to: extracted)
        let text = try String(contentsOf: extracted.appending(path: "folder/note.txt"), encoding: .utf8)
        #expect(text == "hello zip")

        let slip = root.appending(path: "slip.zip")
        try ZipArchive.storedArchive(entries: [
            ("../escape.txt", Data("nope".utf8))
        ]).write(to: slip)
        #expect(throws: ZipArchiveError.unsafePath) {
            try ZipArchive.extractAll(from: slip, to: extracted.appending(path: "slip"))
        }
    }

    @Test func librarySnapshotOmitsImportedFiles() async throws {
        let context = try InMemoryStore.makeContext()
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let pdf = try writePDF(title: "Local Only", to: root.appending(path: "local.pdf"))
        _ = try await ImportedDocumentService(store: ImportedDocumentStore(rootURL: root))
            .importFile(at: pdf, in: context)

        let document = try LibraryMerge.snapshot(from: context)
        #expect(document.articles.isEmpty)
    }

    @Test func retentionRemovesImportedFiles() async throws {
        let context = try InMemoryStore.makeContext()
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let pdf = try writePDF(title: "Old Paper", to: root.appending(path: "old.pdf"))
        let article = try await ImportedDocumentService(store: ImportedDocumentStore(rootURL: root))
            .importFile(at: pdf, in: context)
        let stored = try #require(article.enclosureURL)
        article.state = .read
        article.isRemoteStarred = false
        article.publishedAt = .now.addingTimeInterval(-10 * 86_400)
        try context.save()

        #expect(FileManager.default.fileExists(atPath: stored.path))
        let removed = try ArticleRetentionService().purge(in: context, olderThanDays: 7)
        #expect(removed == 1)
        #expect(!FileManager.default.fileExists(atPath: stored.path))
    }

    @Test func rejectsUnsupportedFiles() async throws {
        let context = try InMemoryStore.makeContext()
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let text = root.appending(path: "notes.txt")
        try Data("just text".utf8).write(to: text)
        await #expect(throws: ImportedDocumentError.unsupportedType) {
            _ = try await ImportedDocumentService(store: ImportedDocumentStore(rootURL: root))
                .importFile(at: text, in: context)
        }
    }

    private func temporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "OneFeed-import-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writePDF(title: String, to url: URL) throws -> URL {
        let document = PDFDocument()
        document.insert(PDFPage(), at: 0)
        document.documentAttributes = [PDFDocumentAttribute.titleAttribute: title]
        guard document.write(to: url) else { throw ImportedDocumentError.invalidPDF }
        return url
    }

    private func writeEPUB(
        title: String,
        author: String?,
        body: String,
        to url: URL,
        encrypted: Bool = false
    ) throws -> URL {
        let creator = author.map { "<dc:creator>\($0)</dc:creator>" } ?? ""
        var entries: [(name: String, data: Data)] = [
            ("mimetype", Data("application/epub+zip".utf8)),
            ("META-INF/container.xml", Data("""
            <?xml version="1.0"?>
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
              <rootfiles>
                <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
              </rootfiles>
            </container>
            """.utf8)),
            ("OEBPS/content.opf", Data("""
            <?xml version="1.0"?>
            <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid" version="2.0">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:title>\(title)</dc:title>
                \(creator)
                <dc:identifier id="bookid">test-book</dc:identifier>
              </metadata>
              <manifest>
                <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
              </manifest>
              <spine>
                <itemref idref="ch1"/>
              </spine>
            </package>
            """.utf8)),
            ("OEBPS/ch1.xhtml", Data("""
            <?xml version="1.0"?>
            <html xmlns="http://www.w3.org/1999/xhtml"><body>\(body)</body></html>
            """.utf8))
        ]
        if encrypted {
            entries.append(("META-INF/encryption.xml", Data("<encryption/>".utf8)))
        }
        try ZipArchive.storedArchive(entries: entries).write(to: url)
        return url
    }
}
