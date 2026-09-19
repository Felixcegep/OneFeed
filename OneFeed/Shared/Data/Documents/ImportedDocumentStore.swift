import Foundation

nonisolated struct ImportedDocumentStore: Sendable {
    let rootURL: URL

    static let shared = ImportedDocumentStore()

    init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.rootURL = support.appending(path: "ImportedDocuments", directoryHint: .isDirectory)
        }
    }

    func fileURL(hash: String, kind: ImportedDocumentKind) -> URL {
        rootURL.appending(path: "\(hash).\(kind.fileExtension)")
    }

    func extractedDirectory(hash: String) -> URL {
        rootURL.appending(path: hash, directoryHint: .isDirectory)
    }

    func copy(_ source: URL, hash: String, kind: ImportedDocumentKind) throws -> URL {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let destination = fileURL(hash: hash, kind: kind)
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    func remove(hash: String, kind: ImportedDocumentKind) {
        try? FileManager.default.removeItem(at: fileURL(hash: hash, kind: kind))
        try? FileManager.default.removeItem(at: extractedDirectory(hash: hash))
    }

    func removeFiles(for article: Article) {
        if let url = article.enclosureURL {
            try? FileManager.default.removeItem(at: url)
            let extracted = url.deletingPathExtension()
            if extracted != url {
                try? FileManager.default.removeItem(at: extracted)
            }
        }
        guard let kind = ImportedDocumentKind(contentKind: article.contentKind),
              let hash = Self.hash(fromGuid: article.guid) else { return }
        remove(hash: hash, kind: kind)
    }

    func resolvedFileURL(for article: Article) -> URL? {
        if let url = article.enclosureURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        guard let kind = ImportedDocumentKind(contentKind: article.contentKind),
              let hash = Self.hash(fromGuid: article.guid) else { return nil }
        let url = fileURL(hash: hash, kind: kind)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func hash(fromGuid guid: String) -> String? {
        guard guid.hasPrefix("imported:") else { return nil }
        let rest = guid.dropFirst("imported:".count)
        guard let colon = rest.firstIndex(of: ":") else { return nil }
        let hash = String(rest[rest.index(after: colon)...])
        return hash.isEmpty ? nil : hash
    }
}
