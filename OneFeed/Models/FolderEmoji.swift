import Foundation

nonisolated enum FolderEmoji {
    private static let defaults: [String: String] = [
        "must read": "📌",
        "builders": "🧱",
        "philosophy": "💭",
        "programming & software": "💻",
        "security & systems": "🔐",
        "business": "📈",
        "geopolitics": "🌍",
        "fitness": "💪",
        "entertainment": "🎬",
        "à scanner": "👀",
        "a scanner": "👀",
        "papers": "📄",
        "archive": "📦",
        "unfiled": "📁"
    ]

    private static let fallbacks = ["📁", "📂", "🗂️", "📓", "📎", "🏷️", "🗞️", "📚"]

    static func glyph(for name: String) -> String {
        let key = normalize(name)
        if let stored = storedMap()[key], !stored.isEmpty { return stored }
        if let suggested = defaults[key] { return suggested }
        if let heuristic = heuristic(for: key) { return heuristic }
        let index = stableIndex(key) % fallbacks.count
        return fallbacks[index]
    }

    static func set(_ emoji: String, for name: String) {
        let trimmed = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var map = storedMap()
        map[normalize(name)] = trimmed
        UserDefaults.standard.set(map, forKey: AppPreferenceKey.folderEmojis)
    }

    static func remove(for name: String) {
        var map = storedMap()
        map.removeValue(forKey: normalize(name))
        UserDefaults.standard.set(map, forKey: AppPreferenceKey.folderEmojis)
    }

    static func resetStored() {
        UserDefaults.standard.removeObject(forKey: AppPreferenceKey.folderEmojis)
    }

    private static func storedMap() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: AppPreferenceKey.folderEmojis) as? [String: String] ?? [:]
    }

    private static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func heuristic(for key: String) -> String? {
        if key.contains("tech") || key.contains("code") || key.contains("program") { return "💻" }
        if key.contains("secur") || key.contains("privacy") { return "🔐" }
        if key.contains("politic") || key.contains("world") { return "🌍" }
        if key.contains("fit") || key.contains("health") { return "💪" }
        if key.contains("design") { return "🎨" }
        if key.contains("music") || key.contains("audio") { return "🎵" }
        if key.contains("news") { return "📰" }
        if key.contains("science") || key.contains("research") { return "🔬" }
        if key.contains("film") || key.contains("tv") || key.contains("watch") { return "🎬" }
        if key.contains("archive") { return "📦" }
        return nil
    }

    private static func stableIndex(_ key: String) -> Int {
        abs(key.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
    }
}

enum FolderEmojiPalette {
    struct Category: Identifiable {
        let title: String
        let glyphs: [String]
        var id: String { title }
    }

    static let categories: [Category] = [
        Category(title: "Suggested", glyphs: [
            "📌", "🧱", "💭", "💻", "🔐", "📈", "🌍", "💪", "🎬", "👀", "📄", "📦", "📁"
        ]),
        Category(title: "Reading", glyphs: [
            "📚", "📖", "🗞️", "📝", "📓", "⭐️", "🔥", "💡", "🧠", "✏️", "🔖", "📎"
        ]),
        Category(title: "Work", glyphs: [
            "🛠️", "⚙️", "🧪", "🚀", "🛰️", "🏗️", "📊", "🧭", "🎯", "💼", "🧑‍💻", "🤖"
        ]),
        Category(title: "Places", glyphs: [
            "🏠", "🏙️", "🌳", "🌊", "⛰️", "🌙", "☀️", "☁️", "🗺️", "🏛️", "☕", "🎧"
        ]),
        Category(title: "Marks", glyphs: [
            "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "✅", "⚡️", "✨", "🔔", "🏷️"
        ])
    ]
}
