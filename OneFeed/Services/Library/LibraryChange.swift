import Foundation
import SwiftData

enum LibraryChange {
    static func note(_ article: Article) {
        article.touchLibrary()
        LibrarySyncService.shared.schedulePush()
    }

    static func note(_ feed: Feed) {
        feed.touchLibrary()
        LibrarySyncService.shared.schedulePush()
    }

    static func noteRemovedFeed(_ feed: Feed) {
        LibraryFolderStore.recordTombstone(feedURL: feed.feedURL)
        LibrarySyncService.shared.schedulePush()
    }

    static func noteStructureChanged() {
        LibrarySyncService.shared.schedulePush()
    }
}
