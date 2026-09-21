import Foundation
import UniformTypeIdentifiers

nonisolated enum ImportedDocumentKind: String, Sendable {
    case pdf
    case epub

    var fileExtension: String { rawValue }

    var mimeType: String {
        switch self {
        case .pdf: "application/pdf"
        case .epub: "application/epub+zip"
        }
    }

    init?(contentKind: String) {
        self.init(rawValue: contentKind)
    }

    func guid(hash: String) -> String {
        "imported:\(rawValue):\(hash)"
    }

    func identityURL(hash: String) -> URL {
        URL(string: "onefeed-imported://\(rawValue)/\(hash)")!
    }

    static var readableTypes: [UTType] { [.pdf, .epub] }

    static func infer(url: URL, contentType: UTType? = nil, mime: String? = nil) -> Self? {
        if let contentType {
            if contentType.conforms(to: .pdf) { return .pdf }
            if contentType.conforms(to: .epub) { return .epub }
        }
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            if type.conforms(to: .pdf) { return .pdf }
            if type.conforms(to: .epub) { return .epub }
        }
        if let mime {
            let lower = mime.lowercased()
            if lower.contains("application/pdf") { return .pdf }
            if lower.contains("epub") { return .epub }
        }
        switch url.pathExtension.lowercased() {
        case "pdf": return .pdf
        case "epub": return .epub
        default: return nil
        }
    }

    static func infer(magic: Data) -> Self? {
        if magic.starts(with: Data("%PDF".utf8)) { return .pdf }
        return nil
    }
}

enum ImportedDocumentError: LocalizedError, Equatable {
    case unsupportedType
    case unreadable
    case tooLarge
    case locked
    case invalidPDF
    case invalidEPUB
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedType:
            "OneFeed can import PDF and EPUB files."
        case .unreadable:
            "OneFeed couldn’t read that file."
        case .tooLarge:
            "That file is too large to import."
        case .locked:
            "That book is locked. OneFeed can only import an unlocked EPUB."
        case .invalidPDF:
            "That file isn’t a readable PDF."
        case .invalidEPUB:
            "That file isn’t a readable EPUB."
        case .downloadFailed:
            "OneFeed couldn’t download that file."
        }
    }
}
