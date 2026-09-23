import Foundation
import Testing
@testable import OneFeed

@MainActor
struct FolderEmojiTests {
    @Test func seededFoldersHaveStableIcons() {
        FolderEmoji.resetStored()
        #expect(FolderEmoji.glyph(for: "Must read") == "📌")
        #expect(FolderEmoji.glyph(for: "Builders") == "🧱")
        #expect(FolderEmoji.glyph(for: "Philosophy") == "💭")
        #expect(FolderEmoji.glyph(for: "Programming & Software") == "💻")
        #expect(FolderEmoji.glyph(for: "Security & Systems") == "🔐")
        #expect(FolderEmoji.glyph(for: "À scanner") == "👀")
        #expect(FolderEmoji.glyph(for: "Archive") == "📦")
        #expect(FolderEmoji.glyph(for: "Unfiled") == "📁")
    }

    @Test func userChoiceOverridesTheDefault() {
        FolderEmoji.resetStored()
        FolderEmoji.set("🚀", for: "Builders")
        #expect(FolderEmoji.glyph(for: "Builders") == "🚀")
        #expect(FolderEmoji.glyph(for: "builders") == "🚀")
        FolderEmoji.remove(for: "Builders")
        #expect(FolderEmoji.glyph(for: "Builders") == "🧱")
        FolderEmoji.resetStored()
    }

    @Test func removingAFolderClearsItsIcon() {
        FolderEmoji.resetStored()
        FolderStore.remember("Emoji Test Folder")
        FolderEmoji.set("🎯", for: "Emoji Test Folder")
        FolderStore.remove("Emoji Test Folder")
        #expect(FolderEmoji.glyph(for: "Emoji Test Folder") != "🎯")
        FolderEmoji.resetStored()
    }

    @Test func draggedFolderOrderIsKept() {
        let names = ["Zed Folder", "Alpha Folder", "Middle Folder"]
        defer { names.forEach(FolderStore.remove) }
        FolderStore.setOrder(names)
        FolderStore.remember("Tail Folder")
        let stored = FolderStore.knownNames()
        let zed = stored.firstIndex(of: "Zed Folder")
        let alpha = stored.firstIndex(of: "Alpha Folder")
        let middle = stored.firstIndex(of: "Middle Folder")
        let tail = stored.firstIndex(of: "Tail Folder")
        #expect(zed != nil && alpha != nil && middle != nil && tail != nil)
        #expect(zed! < alpha! && alpha! < middle! && middle! < tail!)

        let feeds = names.map { name in
            Feed(title: name, feedURL: URL(string: "https://example.com/\(name.replacingOccurrences(of: " ", with: "-"))")!, folderName: name)
        }
        #expect(FeedFolderGrouping.groups(from: feeds).map(\.name) == names)
    }

    @Test func unknownFoldersStayStableAcrossCalls() {
        FolderEmoji.resetStored()
        let first = FolderEmoji.glyph(for: "Deep Cuts")
        let second = FolderEmoji.glyph(for: "Deep Cuts")
        #expect(first == second)
        #expect(!first.isEmpty)
    }
}
