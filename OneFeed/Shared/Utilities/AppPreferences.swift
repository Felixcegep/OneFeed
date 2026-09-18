import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum ReaderFontChoice: String, CaseIterable, Identifiable {
    case sans
    case serif
    case mono

    var id: Self { self }
    var label: String {
        switch self {
        case .sans: "Sans serif"
        case .serif: "Serif"
        case .mono: "Monospaced"
        }
    }
}

enum ReaderTextSize: String, CaseIterable, Identifiable {
    case small
    case standard
    case large

    var id: Self { self }
    var label: String { self == .standard ? "Default" : rawValue.capitalized }
    var basePoints: CGFloat {
        switch self { case .small: 15; case .standard: 16; case .large: 19 }
    }
    var points: CGFloat {
        #if canImport(UIKit)
        UIFontMetrics(forTextStyle: .body).scaledValue(for: basePoints)
        #else
        basePoints
        #endif
    }
}

enum ArticleRetentionChoice: Int, CaseIterable, Identifiable {
    case threeDays = 3
    case sevenDays = 7
    case fourteenDays = 14
    case thirtyDays = 30
    case forever = 0

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .threeDays: "3 days"
        case .sevenDays: "7 days"
        case .fourteenDays: "14 days"
        case .thirtyDays: "30 days"
        case .forever: "Forever"
        }
    }
}

enum AppPreferenceKey {
    static let completedOnboarding = "completedOnboarding"
    static let readerFont = "readerFont"
    static let readerTextSize = "readerTextSize"
    static let didSeedTinyRSSCatalog = "didSeedTinyRSSCatalog"
    static let seedCatalogVersion = "seedCatalogVersion"
    static let articleRetentionDays = "articleRetentionDays"
    static let lastSuccessfulRefresh = "lastSuccessfulRefresh"
    static let knownFolderNames = "knownFolderNames"
    static let folderEmojis = "folderEmojis"
    static let libraryFolderBookmark = "libraryFolderBookmark"
    static let libraryBookmarkIsFile = "libraryBookmarkIsFile"
    static let libraryTombstones = "libraryTombstones"
    static let libraryDisplayName = "libraryDisplayName"
    static let cloudFileLinkRecord = "cloudFileLinkRecord"
}

/// Folder names the user created (even before any feed is filed there).
enum FolderStore {
    static func knownNames() -> [String] {
        let stored = UserDefaults.standard.stringArray(forKey: AppPreferenceKey.knownFolderNames) ?? []
        return normalize(stored)
    }

    static func remember(_ names: [String]) {
        var merged = Set(knownNames())
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            merged.insert(trimmed)
        }
        UserDefaults.standard.set(normalize(Array(merged)), forKey: AppPreferenceKey.knownFolderNames)
    }

    static func remember(_ name: String) {
        remember([name])
    }

    static func remove(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = knownNames().filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        UserDefaults.standard.set(next, forKey: AppPreferenceKey.knownFolderNames)
        FolderEmoji.remove(for: trimmed)
    }

    /// Known empty folders plus folders that already contain feeds.
    static func allNames(from feeds: [Feed]) -> [String] {
        var names = Set(knownNames())
        for feed in feeds {
            if let folder = feed.folderName?.trimmingCharacters(in: .whitespacesAndNewlines), !folder.isEmpty {
                names.insert(folder)
            }
        }
        return normalize(Array(names))
    }

    static func normalize(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            ordered.append(trimmed)
        }
        return ordered.sorted(by: FeedFolderGrouping.compareFolderNames)
    }
}
