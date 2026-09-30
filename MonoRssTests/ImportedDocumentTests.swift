import CoreText
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

    @Test func paperWithoutMetadataUsesTheFirstPageTitle() {
        let page = """
        How Good Are Query Optimizers, Really?
        Viktor Leis
        TUM
        leis@in.tum.de
        Peter Boncz
        ABSTRACT
        Finding a good join order is crucial for query performance.
        INTRODUCTION
        The rest of the paper.
        """
        let heading = ImportedDocumentService.pdfHeading(from: page)
        #expect(heading.title == "How Good Are Query Optimizers, Really?")
        #expect(heading.author == "Viktor Leis, Peter Boncz")
        #expect(heading.summary?.contains("Finding a good join order") == true)
        #expect(heading.summary?.contains("rest of the paper") != true)
    }

    @Test func importingATextOnlyPDFReadsTheFirstPage() async throws {
        let context = try InMemoryStore.makeContext()
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let pdf = try writeTextPDF(
            """
            How Good Are Query Optimizers, Really?
            Viktor Leis
            TUM
            leis@in.tum.de
            ABSTRACT
            Finding a good join order is crucial for query performance.
            """,
            to: root.appending(path: "p204-leis.pdf")
        )

        let article = try await ImportedDocumentService(store: ImportedDocumentStore(rootURL: root))
            .importFile(at: pdf, in: context)

        #expect(article.title == "How Good Are Query Optimizers, Really?")
        #expect(article.author == "Viktor Leis")
        #expect(article.summary?.contains("Finding a good join order") == true)
        #expect(article.contentKind == "pdf")
        #expect(article.state == .saved)
        #expect(article.contentHTML?.contains("Finding a good join order") == true)
        #expect(article.contentHTML?.contains("<p>") == true)
    }

    @Test func pdfTextBlocksJoinWrappedLinesAndKeepParagraphs() {
        let blocks = ImportedDocumentService.textBlocks(from: """
        Finding a good join order is crucial
        for query performance.

        ABSTRACT
        opti-
        mizers really matter.
        """)
        #expect(blocks.count == 2)
        #expect(blocks[0] == "Finding a good join order is crucial for query performance.")
        #expect(blocks[1].contains("ABSTRACT"))
        #expect(blocks[1].contains("optimizers really matter."))
        let html = blocks.map { ImportedDocumentService.persistedHTML("<p>\($0)</p>") ?? "" }.joined()
        #expect(html.contains("<p>Finding a good join order"))
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

    @Test func addingAPDFURLCreatesAReadableSource() async throws {
        let context = try InMemoryStore.makeContext()
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let address = "https://www.vldb.org/pvldb/vol9/p204-leis.pdf"
        let pdf = try writePDF(title: "How Good Are Query Optimizers, Really?", to: root.appending(path: "p204-leis.pdf"))
        let bytes = try Data(contentsOf: pdf)
        let url = try #require(URL(string: address))
        SourceImportURLProtocol.setResponse(bytes, for: url, mime: "application/pdf")
        let service = FeedService(
            session: SourceImportURLProtocol.session(),
            youtubeMetadata: YouTubeMetadataService(session: SourceImportURLProtocol.session()),
            documentSession: SourceImportURLProtocol.session(),
            documents: ImportedDocumentStore(rootURL: root)
        )

        #expect(FeedService.importsWithoutRSS(address))
        let feed = try await service.addSource(from: address, folderName: "Papers", in: context)
        let again = try await service.addSource(from: address, in: context)

        #expect(again.id == feed.id)
        #expect(feed.contentKind == "pdf")
        #expect(feed.folderName == "Papers")
        #expect(feed.title == "How Good Are Query Optimizers, Really?")
        #expect(!feed.refreshesOverRSS)
        let articles = try context.fetch(FetchDescriptor<Article>())
        #expect(articles.count == 1)
        let article = try #require(articles.first)
        #expect(article.contentKind == "pdf")
        #expect(article.state == .queued)
        #expect(article.feed?.id == feed.id)
        #expect(article.url?.absoluteString == address)
        #expect(FileManager.default.fileExists(atPath: try #require(article.enclosureURL).path))
        #expect(try context.fetchCount(FetchDescriptor<Feed>()) == 1)
    }

    @Test func addingASourceLinksAnExistingQueuedPDF() async throws {
        let context = try InMemoryStore.makeContext()
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let pdf = try writePDF(title: "Queued Paper", to: root.appending(path: "queued.pdf"))
        let store = ImportedDocumentStore(rootURL: root)
        let queued = try await ImportedDocumentService(store: store).importFile(at: pdf, in: context)
        let address = "https://example.com/queued.pdf"
        let url = try #require(URL(string: address))
        SourceImportURLProtocol.setResponse(try Data(contentsOf: pdf), for: url, mime: "application/pdf")
        let service = FeedService(
            session: SourceImportURLProtocol.session(),
            documentSession: SourceImportURLProtocol.session(),
            documents: store
        )

        let feed = try await service.addSource(from: address, in: context)
        let articles = try context.fetch(FetchDescriptor<Article>())

        #expect(articles.count == 1)
        #expect(articles[0].id == queued.id)
        #expect(queued.state == .saved)
        #expect(queued.feed?.id == feed.id)
        #expect(feed.contentKind == "pdf")
    }

    @Test func addingAnArticlePageWithoutAFeedCreatesAPageSource() async throws {
        let context = try InMemoryStore.makeContext()
        let address = "https://example.com/stories/join-order"
        let url = try #require(URL(string: address))
        let html = """
        <!DOCTYPE html><html><head><title>Join Order</title></head>
        <body><p>Finding a good join order is crucial for query performance.</p></body></html>
        """
        SourceImportURLProtocol.setResponse(Data(html.utf8), for: url, mime: "text/html")
        let service = FeedService(session: SourceImportURLProtocol.session())

        let feed = try await service.addSource(from: address, in: context)
        let article = try #require(try context.fetch(FetchDescriptor<Article>()).first)

        #expect(feed.contentKind == "page")
        #expect(feed.title == "Join Order")
        #expect(!feed.refreshesOverRSS)
        #expect(article.contentKind == "article")
        #expect(article.state == .queued)
        #expect(article.feed?.id == feed.id)
        #expect(article.title == "Join Order")
    }

    @Test func addingAFeedStillCreatesASubscription() async throws {
        let context = try InMemoryStore.makeContext()
        let address = "https://example.com/rss.xml"
        let url = try #require(URL(string: address))
        let xml = """
        <rss version="2.0"><channel><title>VLDB</title>
        <item><guid>paper-1</guid><title>Optimizers</title><link>https://example.com/papers/1</link><description>Hello</description></item>
        </channel></rss>
        """
        SourceImportURLProtocol.setResponse(Data(xml.utf8), for: url, mime: "application/rss+xml")
        let service = FeedService(
            session: SourceImportURLProtocol.session(),
            youtubeMetadata: YouTubeMetadataService(session: SourceImportURLProtocol.session())
        )

        let feed = try await service.addSource(from: address, in: context)

        #expect(feed.contentKind == "article")
        #expect(feed.refreshesOverRSS)
        #expect(feed.title == "VLDB")
        #expect(try context.fetchCount(FetchDescriptor<Article>()) == 1)
    }

    @Test func plainTextWithoutAFeedStillFailsDiscovery() async throws {
        let context = try InMemoryStore.makeContext()
        let address = "https://example.com/notes"
        let url = try #require(URL(string: address))
        SourceImportURLProtocol.setResponse(Data("not a feed".utf8), for: url, mime: "text/plain")
        let service = FeedService(session: SourceImportURLProtocol.session())

        do {
            _ = try await service.addSource(from: address, in: context)
            Issue.record("Expected discovery to fail")
        } catch {
            #expect(error.localizedDescription == FeedServiceError.discoveryFailed.errorDescription)
        }
    }

    @Test func refreshSkipsDocumentAndPageSources() async throws {
        let context = try InMemoryStore.makeContext()
        let pdf = Feed(
            title: "Paper",
            feedURL: URL(string: "https://skip-refresh.test/paper.pdf")!,
            contentKind: "pdf"
        )
        let page = Feed(
            title: "Essay",
            feedURL: URL(string: "https://skip-refresh.test/essay")!,
            contentKind: "page"
        )
        context.insert(pdf)
        context.insert(page)
        try context.save()
        let service = FeedService(session: SourceImportURLProtocol.session())

        try await service.refreshAll(in: context)

        #expect(pdf.lastFetchedAt == nil)
        #expect(page.lastFetchedAt == nil)
        #expect(SourceImportURLProtocol.requests(forHost: "skip-refresh.test").isEmpty)
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

    private func writeTextPDF(_ text: String, to url: URL) throws -> URL {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw ImportedDocumentError.invalidPDF
        }
        context.beginPDFPage(nil)
        let font = CTFontCreateWithName("Helvetica" as CFString, 14, nil)
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: box.insetBy(dx: 48, dy: 72), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attributed.length), path, nil)
        CTFrameDraw(frame, context)
        context.endPDFPage()
        context.closePDF()
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

    @Test func aSecondImportWaitsUntilTheFirstFinishes() async {
        DocumentImportLane.resetForTests()
        let gate = ImportOverlapGate()
        let first = Task {
            try await DocumentImportLane.run { await gate.enter() }
        }
        for _ in 0..<50 where gate.entered == 0 {
            await Task.yield()
        }
        let second = Task {
            try await DocumentImportLane.run { await gate.enter() }
        }
        for _ in 0..<20 {
            await Task.yield()
        }
        gate.release()
        _ = try? await first.value
        _ = try? await second.value
        #expect(gate.entered == 2)
        #expect(gate.maxInFlight == 1)
        DocumentImportLane.resetForTests()
    }
}

@MainActor
private final class ImportOverlapGate {
    private(set) var entered = 0
    private(set) var maxInFlight = 0
    private var inFlight = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func enter() async {
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        entered += 1
        if entered == 1 {
            await withCheckedContinuation { continuation = $0 }
        }
        inFlight -= 1
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private final class SourceImportURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [String: (Data, HTTPURLResponse)] = [:]
    nonisolated(unsafe) private static var requested: [URL] = []

    static func setResponse(_ data: Data, for url: URL, status: Int = 200, mime: String? = nil) {
        var headers: [String: String] = [:]
        if let mime { headers["Content-Type"] = mime }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
        lock.lock()
        responses[url.absoluteString] = (data, response)
        lock.unlock()
    }

    static func requests(forHost host: String) -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return requested.filter { $0.host() == host }
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SourceImportURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let client, let url = request.url else { return }
        Self.lock.lock()
        Self.requested.append(url)
        let response = Self.responses[url.absoluteString]
        Self.lock.unlock()
        guard let response else {
            client.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client.urlProtocol(self, didReceive: response.1, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: response.0)
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
