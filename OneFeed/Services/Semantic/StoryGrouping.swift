import Foundation

struct FeedStoryRow: Identifiable {
    enum Kind {
        case article(Article, caption: String?)
        case moreSources(clusterID: UUID, count: Int)
    }

    let id: String
    let kind: Kind
}

enum StoryGrouping {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .numeric
        formatter.unitsStyle = .full
        return formatter
    }()

    static func moreSourcesTitle(count: Int) -> String {
        if count == 1 {
            return "1 more source about this story"
        }
        return "\(count) more sources about this story"
    }

    static func similarCaption(matchedConsumedAt: Date?, now: Date = .now) -> String? {
        guard let matchedConsumedAt else { return nil }
        let relative = relativeFormatter.localizedString(for: matchedConsumedAt, relativeTo: now)
        return "Similar to something you read \(relative)"
    }

    static func captions(
        for articles: [Article],
        memories: [ContentMemory],
        openArticles: [Article] = [],
        now: Date = .now
    ) -> [UUID: String] {
        var byKey: [String: ContentMemory] = [:]
        byKey.reserveCapacity(memories.count)
        for memory in memories {
            byKey[memory.identityKey] = memory
        }
        let pool = openArticles.isEmpty ? articles : openArticles
        var clusterCounts: [UUID: Int] = [:]
        var sameStoryClusters = Set<UUID>()
        for article in pool {
            guard let memory = byKey[ArticleIdentity.identityKey(for: article)],
                  let clusterID = memory.storyClusterID else { continue }
            clusterCounts[clusterID, default: 0] += 1
            if memory.relationshipRaw == ContentRelationship.sameStory.rawValue {
                sameStoryClusters.insert(clusterID)
            }
        }
        var captions: [UUID: String] = [:]
        for article in articles {
            let memory = byKey[ArticleIdentity.identityKey(for: article)]
            var lines: [String] = []
            if let similar = similarCaption(matchedConsumedAt: memory?.matchedConsumedAt, now: now) {
                lines.append(similar)
            }
            if let clusterID = memory?.storyClusterID, sameStoryClusters.contains(clusterID) {
                let others = (clusterCounts[clusterID] ?? 0) - 1
                if others > 0 {
                    lines.append(moreSourcesTitle(count: others))
                }
            }
            if !lines.isEmpty {
                captions[article.id] = lines.joined(separator: "\n")
            }
        }
        return captions
    }

    /// Search is already applied. Exact and near copies drop out; same-story clusters collapse to the newest source.
    static func rows(
        from articles: [Article],
        memories: [ContentMemory],
        expandedClusterIDs: Set<UUID>,
        now: Date = .now
    ) -> [FeedStoryRow] {
        var byKey: [String: ContentMemory] = [:]
        byKey.reserveCapacity(memories.count)
        for memory in memories {
            byKey[memory.identityKey] = memory
        }

        let visible = articles.filter { article in
            let raw = byKey[ArticleIdentity.identityKey(for: article)]?.relationshipRaw
            return raw != ContentRelationship.exactDuplicate.rawValue
                && raw != ContentRelationship.nearDuplicate.rawValue
        }

        var members: [UUID: [Article]] = [:]
        var sameStoryClusters = Set<UUID>()
        for article in visible {
            guard let memory = byKey[ArticleIdentity.identityKey(for: article)],
                  let clusterID = memory.storyClusterID else { continue }
            members[clusterID, default: []].append(article)
            if memory.relationshipRaw == ContentRelationship.sameStory.rawValue {
                sameStoryClusters.insert(clusterID)
            }
        }

        var emitted = Set<UUID>()
        var rows: [FeedStoryRow] = []
        rows.reserveCapacity(visible.count)
        for article in visible {
            let memory = byKey[ArticleIdentity.identityKey(for: article)]
            if let clusterID = memory?.storyClusterID, sameStoryClusters.contains(clusterID) {
                guard emitted.insert(clusterID).inserted else { continue }
                let ordered = (members[clusterID] ?? [article]).sorted { $0.publishedAt > $1.publishedAt }
                let primary = ordered[0]
                let others = Array(ordered.dropFirst())
                let primaryMemory = byKey[ArticleIdentity.identityKey(for: primary)]
                rows.append(FeedStoryRow(
                    id: primary.id.uuidString,
                    kind: .article(
                        primary,
                        caption: similarCaption(matchedConsumedAt: primaryMemory?.matchedConsumedAt, now: now)
                    )
                ))
                if !others.isEmpty {
                    rows.append(FeedStoryRow(
                        id: "more-\(clusterID.uuidString)",
                        kind: .moreSources(clusterID: clusterID, count: others.count)
                    ))
                    if expandedClusterIDs.contains(clusterID) {
                        for other in others {
                            rows.append(FeedStoryRow(
                                id: other.id.uuidString,
                                kind: .article(other, caption: nil)
                            ))
                        }
                    }
                }
                continue
            }
            rows.append(FeedStoryRow(
                id: article.id.uuidString,
                kind: .article(article, caption: nil)
            ))
        }
        return rows
    }
}
