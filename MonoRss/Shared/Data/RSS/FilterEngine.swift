import Foundation

nonisolated enum FilterAction: String, Sendable {
    case keep = "KEEP"
    case drop = "DROP"
    case tag = "TAG"
    case star = "STAR"
}

nonisolated enum FilterField: String, Sendable {
    case title
    case author
    case url
    case content
    case feed
}

nonisolated struct FilterRule: Sendable {
    let action: FilterAction
    let field: FilterField
    let pattern: String
    let isRegex: Bool
    let tag: String?

    init(action: FilterAction, field: FilterField, pattern: String, isRegex: Bool = false, tag: String? = nil) {
        self.action = action
        self.field = field
        self.pattern = pattern
        self.isRegex = isRegex
        self.tag = tag
    }
}

nonisolated struct FilterEntry: Sendable {
    let title: String
    let author: String
    let url: String
    let content: String

    init(title: String = "", author: String = "", url: String = "", content: String = "") {
        self.title = title
        self.author = author
        self.url = url
        self.content = content
    }
}

nonisolated struct FilterFeedContext: Sendable {
    let title: String
    let url: String

    init(title: String = "", url: String = "") {
        self.title = title
        self.url = url
    }
}

nonisolated struct FilterResult: Sendable {
    var drop: Bool = false
    var star: Bool = false
    var tags: [String] = []
}

nonisolated enum FilterEngine: Sendable {
    static func apply(rules: [FilterRule], entry: FilterEntry, feed: FilterFeedContext) -> FilterResult {
        var result = FilterResult()
        guard !rules.isEmpty else { return result }

        let keepRules = rules.filter { $0.action == .keep }
        var keepHit = false

        for rule in rules where matches(rule, entry: entry, feed: feed) {
            switch rule.action {
            case .drop:
                result.drop = true
            case .keep:
                keepHit = true
            case .star:
                result.star = true
            case .tag:
                let tag = rule.tag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !tag.isEmpty, !result.tags.contains(tag) {
                    result.tags.append(tag)
                }
            }
        }

        if !keepRules.isEmpty, !keepHit {
            result.drop = true
        }
        if result.drop {
            result.star = false
            result.tags = []
        }
        return result
    }

    static func blockedWordRules(from text: String) -> [FilterRule] {
        let separators = CharacterSet(charactersIn: ",\n")
        let words = text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return words.flatMap { word in
            [
                FilterRule(action: .drop, field: .title, pattern: word),
                FilterRule(action: .drop, field: .content, pattern: word),
            ]
        }
    }

    private static func haystack(field: FilterField, entry: FilterEntry, feed: FilterFeedContext) -> String {
        switch field {
        case .feed: return "\(feed.title) \(feed.url)"
        case .title: return entry.title
        case .author: return entry.author
        case .url: return entry.url
        case .content: return entry.content
        }
    }

    private static func matches(_ rule: FilterRule, entry: FilterEntry, feed: FilterFeedContext) -> Bool {
        let text = haystack(field: rule.field, entry: entry, feed: feed)
        if rule.isRegex {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { return false }
            let range = NSRange(text.startIndex..., in: text)
            return regex.firstMatch(in: text, range: range) != nil
        }
        return text.range(of: rule.pattern, options: .caseInsensitive) != nil
    }
}
