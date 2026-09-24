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
    static func moreSourcesTitle(count: Int) -> String {
        if count == 1 {
            return "1 more source about this story"
        }
        return "\(count) more sources about this story"
    }

    static func similarCaption(matchedConsumedAt: Date?, now: Date = .now) -> String? {
        guard let matchedConsumedAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .numeric
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: matchedConsumedAt, relativeTo: now)
        return "Similar to something you read \(relative)"
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
