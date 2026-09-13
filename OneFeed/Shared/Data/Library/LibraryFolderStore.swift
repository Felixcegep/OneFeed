import Foundation

enum LibraryFolderStore {
    static var fileName: String { LibraryDocumentFormat.fileName }

    static func saveBookmark(for url: URL, isFile: Bool) throws {
        #if os(macOS)
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        let data = try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
        UserDefaults.standard.set(data, forKey: AppPreferenceKey.libraryFolderBookmark)
        UserDefaults.standard.set(isFile, forKey: AppPreferenceKey.libraryBookmarkIsFile)
        UserDefaults.standard.set(displayName(for: url), forKey: AppPreferenceKey.libraryDisplayName)
    }

    static func resolvedURL() throws -> (url: URL, isFile: Bool, isStale: Bool)? {
        guard let data = UserDefaults.standard.data(forKey: AppPreferenceKey.libraryFolderBookmark) else {
            return nil
        }
        var isStale = false
        #if os(macOS)
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        #else
        let url = try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        #endif
        let isFile = UserDefaults.standard.bool(forKey: AppPreferenceKey.libraryBookmarkIsFile)
        return (url, isFile, isStale)
    }

    static func storedDisplayName() -> String? {
        UserDefaults.standard.string(forKey: AppPreferenceKey.libraryDisplayName)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: AppPreferenceKey.libraryFolderBookmark)
        UserDefaults.standard.removeObject(forKey: AppPreferenceKey.libraryBookmarkIsFile)
        UserDefaults.standard.removeObject(forKey: AppPreferenceKey.libraryDisplayName)
    }

    static func displayName(for url: URL) -> String {
        let folder = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        let path = folder.path.lowercased()
        if path.contains("com~apple~clouddocs") || path.contains("mobile documents") {
            return "iCloud Drive"
        }
        if path.contains("google drive") || path.contains("googledrive") || path.contains("com.google.drive") {
            return "Google Drive"
        }
        return folder.lastPathComponent.isEmpty ? folder.path : folder.lastPathComponent
    }

    static func libraryFileURL(from selected: URL, isFile: Bool) -> URL {
        if isFile { return selected }
        return selected.appendingPathComponent(fileName, isDirectory: false)
    }

    static func isConflictCopy(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.contains("conflicted copy") || name.contains("conflict copy")
    }

    static func loadTombstones() -> [LibraryTombstone] {
        guard let data = UserDefaults.standard.data(forKey: AppPreferenceKey.libraryTombstones),
              let decoded = try? LibraryDocumentFormat.decoder().decode([LibraryTombstone].self, from: data) else {
            return []
        }
        return decoded
    }

    static func saveTombstones(_ tombstones: [LibraryTombstone]) {
        if tombstones.isEmpty {
            UserDefaults.standard.removeObject(forKey: AppPreferenceKey.libraryTombstones)
            return
        }
        UserDefaults.standard.set(try? LibraryDocumentFormat.encoder().encode(tombstones), forKey: AppPreferenceKey.libraryTombstones)
    }

    static func recordTombstone(feedURL: URL, at date: Date = .now) {
        let key = ArticleIdentity.feedKey(feedURL)
        var tombstones = loadTombstones()
        if let index = tombstones.firstIndex(where: { $0.feedURL == key }) {
            tombstones[index].deletedAt = max(tombstones[index].deletedAt, date)
        } else {
            tombstones.append(LibraryTombstone(feedURL: key, deletedAt: date))
        }
        saveTombstones(tombstones)
    }
}
