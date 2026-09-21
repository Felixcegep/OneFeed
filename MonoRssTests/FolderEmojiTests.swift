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

    @Test func unknownFoldersStayStableAcrossCalls() {
        FolderEmoji.resetStored()
        let first = FolderEmoji.glyph(for: "Deep Cuts")
        let second = FolderEmoji.glyph(for: "Deep Cuts")
        #expect(first == second)
        #expect(!first.isEmpty)
    }
}
