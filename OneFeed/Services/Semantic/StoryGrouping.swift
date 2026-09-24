import Foundation

struct FeedStoryRow: Identifiable {
    enum Kind {
        case article(Article, caption: String?)
        case moreSources(clusterID: UUID, count: Int)
    }

    let id: String
    let kind: Kind
}

struct StoryCaptionSubject: Sendable {
    var id: UUID
    var identityKey: String
}

struct StoryMemoryMark: Sendable {
    var identityKey: String
    var matchedConsumedAt: Date?
    var storyClusterID: UUID?
    var relationshipRaw: String
}

enum StoryGrouping {
    static func moreSourcesTitle(count: Int) -> String {
        if count == 1 {
            return "1 more source about this story"
        }
        return "\(count) more sources about this story"
    }

    static func similarCaption(matchedConsumedAt: Date?, now: Date = .now, calendar: Calendar = .current) -> String? {
        guard let matchedConsumedAt else { return nil }
        return "Similar to something you read \(OneFeedDateLabel.readWhen(matchedConsumedAt, now: now, calendar: calendar))"
    }

    static func captions(
        for articles: [Article],
        memories: [ContentMemory],
        openArticles: [Article] = [],
        now: Date = .now
    ) -> [UUID: String] {
        captions(
            for: articles.map { StoryCaptionSubject(id: $0.id, identityKey: ArticleIdentity.identityKey(for: $0)) },
            openKeys: openArticles.map { ArticleIdentity.identityKey(for: $0) },
            memories: memories.map {
                StoryMemoryMark(
                    identityKey: $0.identityKey,
                    matchedConsumedAt: $0.matchedConsumedAt,
                    storyClusterID: $0.storyClusterID,
                    relationshipRaw: $0.relationshipRaw
                )
            },
            now: now
        )
    }

    /// Cluster captions from already-copied fields. Safe to run off the main actor.
    static func captions(
        for subjects: [StoryCaptionSubject],
        openKeys: [String],
        memories: [StoryMemoryMark],
        now: Date = .now
    ) -> [UUID: String] {
        var byKey: [String: StoryMemoryMark] = [:]
        byKey.reserveCapacity(memories.count)
        for memory in memories {
            byKey[memory.identityKey] = memory
        }
        let pool = openKeys.isEmpty ? subjects.map(\.identityKey) : openKeys
        var clusterCounts: [UUID: Int] = [:]
        var sameStoryClusters = Set<UUID>()
        for key in pool {
            guard let memory = byKey[key], let clusterID = memory.storyClusterID else { continue }
            clusterCounts[clusterID, default: 0] += 1
            if memory.relationshipRaw == ContentRelationship.sameStory.rawValue {
                sameStoryClusters.insert(clusterID)
            }
        }
        var captions: [UUID: String] = [:]
        for subject in subjects {
            let memory = byKey[subject.identityKey]
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
                captions[subject.id] = lines.joined(separator: "\n")
            }
        }
        return captions
    }

    /// Reads open stories and memories off the main actor, then builds Today’s captions.
    static func captions(for subjects: [StoryCaptionSubject], in container: ModelContainer, now: Date = .now) async -> [UUID: String] {
        let sources = await Task.detached(priority: .utility) {
            captionSources(in: ModelContext(container))
        }.value
        return captions(for: subjects, openKeys: sources.openKeys, memories: sources.memories, now: now)
    }

    private static func captionSources(in context: ModelContext) -> (openKeys: [String], memories: [StoryMemoryMark]) {
        let queued = ArticleState.queued.rawValue
        let current = ArticleState.current.rawValue
        var openDescriptor = FetchDescriptor<Article>(predicate: #Predicate { article in
            article.stateRawValue == queued || article.stateRawValue == current
        })
        openDescriptor.propertiesToFetch = [\.guid, \.url, \.videoID]
        let openArticles = (try? context.fetch(openDescriptor)) ?? []
        var descriptor = FetchDescriptor<ContentMemory>()
        descriptor.propertiesToFetch = [\.identityKey, \.matchedConsumedAt, \.storyClusterID, \.relationshipRaw]
        let memories = (try? context.fetch(descriptor)) ?? []
        return (
            openArticles.map { ArticleIdentity.identityKey(for: $0) },
            memories.map {
                StoryMemoryMark(
                    identityKey: $0.identityKey,
                    matchedConsumedAt: $0.matchedConsumedAt,
                    storyClusterID: $0.storyClusterID,
                    relationshipRaw: $0.relationshipRaw
                )
            }
        )
    }

    /// Search is already applied. Exact and near copies drop out; same-story clusters collapse to the newest source.
    static func rows(
        from articles: [Article],
        placements: [String: StoryPlacement],
        expandedClusterIDs: Set<UUID>,
        now: Date = .now
    ) -> [FeedStoryRow] {
        let visible = articles.filter { article in
            let raw = placements[ArticleIdentity.identityKey(for: article)]?.relationshipRaw
            return raw != ContentRelationship.exactDuplicate.rawValue
                && raw != ContentRelationship.nearDuplicate.rawValue
        }

        var members: [UUID: [Article]] = [:]
        var sameStoryClusters = Set<UUID>()
        for article in visible {
            guard let mark = placements[ArticleIdentity.identityKey(for: article)],
                  let clusterID = mark.storyClusterID else { continue }
            members[clusterID, default: []].append(article)
            if mark.relationshipRaw == ContentRelationship.sameStory.rawValue {
                sameStoryClusters.insert(clusterID)
            }
        }

        var emitted = Set<UUID>()
        var rows: [FeedStoryRow] = []
        rows.reserveCapacity(visible.count)
        for article in visible {
            let key = ArticleIdentity.identityKey(for: article)
            let mark = placements[key]
            if let clusterID = mark?.storyClusterID, sameStoryClusters.contains(clusterID) {
                guard emitted.insert(clusterID).inserted else { continue }
                let ordered = (members[clusterID] ?? [article]).sorted { $0.publishedAt > $1.publishedAt }
                let primary = ordered[0]
                let others = Array(ordered.dropFirst())
                let primaryMark = placements[ArticleIdentity.identityKey(for: primary)]
                rows.append(FeedStoryRow(
                    id: primary.id.uuidString,
                    kind: .article(
                        primary,
                        caption: similarCaption(matchedConsumedAt: primaryMark?.matchedConsumedAt, now: now)
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
                kind: .article(
                    article,
                    caption: similarCaption(matchedConsumedAt: mark?.matchedConsumedAt, now: now)
                )
            ))
        }
        return rows
    }
}

struct StoryListSnap: Sendable {
    var id: UUID
    var feedID: UUID?
    var feedTitle: String?
    var publishedAt: Date
    var title: String
    var aiSummary: String?
    var summary: String?
    var videoID: String?
    var url: URL?
    var guid: String
    var hasRemoteID: Bool
    var stateRaw: String
    var isRemoteStarred: Bool
}

struct StoryRowPlan: Sendable, Identifiable {
    enum Kind: Sendable {
        case article(id: UUID, caption: String?)
        case moreSources(clusterID: UUID, count: Int)
    }

    var id: String
    var kind: Kind
}

/// Same row order as `StoryGrouping.rows`, from copied fields.
nonisolated enum StoryListPlan {
    /// A modest open library can be collapsed on the open screen. A long one, or a search, waits for the off-screen plan.
    static let synchronousRowLimit = 200

    static func rowsOnTheOpenScreen(storyCount: Int, isSearching: Bool) -> Bool {
        !isSearching && storyCount > 0 && storyCount <= synchronousRowLimit
    }

    static func rows(
        destination: FeedBrowseDestination,
        feeds: [UUID: FolderFeedSnap],
        stories: [StoryListSnap],
        placements: [String: StoryPlacement],
        expanded: Set<UUID>,
        query: String,
        now: Date = .now
    ) -> [StoryRowPlan] {
        let open = collapsed(stories.filter { $0.stateRaw == "queued" || $0.stateRaw == "current" }.sorted { $0.publishedAt > $1.publishedAt })
        let inFolder = open.filter { belongs(feedID: $0.feedID, memberships: $0.feedID.flatMap { feeds[$0]?.memberships }, to: destination) }
        let visibleStories = query.isEmpty ? inFolder : inFolder.filter { matches($0, query: query) }
        return rowPlans(from: visibleStories, placements: placements, expanded: expanded, now: now)
    }

    /// Same folder membership as the planned rows. Missing source membership is Unfiled.
    static func belongs(feedID: UUID?, memberships: [String]?, to destination: FeedBrowseDestination) -> Bool {
        switch destination {
        case .unread:
            return true
        case .folder(let folderID):
            guard feedID != nil, let memberships else { return folderID == .unfiled }
            switch folderID {
            case .unfiled:
                return memberships.isEmpty
            case .named(let name):
                return memberships.contains(name)
            }
        }
    }

    private static func matches(_ story: StoryListSnap, query: String) -> Bool {
        if story.title.localizedStandardContains(query) { return true }
        if story.feedTitle?.localizedStandardContains(query) == true { return true }
        return excerpt(story)?.localizedStandardContains(query) == true
    }

    private static func excerpt(_ story: StoryListSnap) -> String? {
        if let aiSummary = story.aiSummary, !aiSummary.isEmpty {
            return ContentClassifier.proseExcerpt(aiSummary, maxCharacters: 280)
        }
        if let summary = story.summary, !summary.isEmpty {
            return ContentClassifier.proseExcerpt(summary, maxCharacters: 220)
        }
        return nil
    }

    private static func rowPlans(
        from stories: [StoryListSnap],
        placements: [String: StoryPlacement],
        expanded: Set<UUID>,
        now: Date
    ) -> [StoryRowPlan] {
        let exact = ContentRelationship.exactDuplicate.rawValue
        let near = ContentRelationship.nearDuplicate.rawValue
        let sameStory = ContentRelationship.sameStory.rawValue
        let visible = stories.filter { story in
            let raw = placements[identityKey(story)]?.relationshipRaw
            return raw != exact && raw != near
        }
        var members: [UUID: [StoryListSnap]] = [:]
        var sameStoryClusters = Set<UUID>()
        for story in visible {
            guard let mark = placements[identityKey(story)], let clusterID = mark.storyClusterID else { continue }
            members[clusterID, default: []].append(story)
            if mark.relationshipRaw == sameStory {
                sameStoryClusters.insert(clusterID)
            }
        }
        var emitted = Set<UUID>()
        var rows: [StoryRowPlan] = []
        for story in visible {
            let key = identityKey(story)
            let mark = placements[key]
            if let clusterID = mark?.storyClusterID, sameStoryClusters.contains(clusterID) {
                guard emitted.insert(clusterID).inserted else { continue }
                let ordered = (members[clusterID] ?? [story]).sorted { $0.publishedAt > $1.publishedAt }
                let primary = ordered[0]
                let others = Array(ordered.dropFirst())
                let primaryMark = placements[identityKey(primary)]
                rows.append(StoryRowPlan(
                    id: primary.id.uuidString,
                    kind: .article(id: primary.id, caption: StoryGrouping.similarCaption(matchedConsumedAt: primaryMark?.matchedConsumedAt, now: now))
                ))
                if !others.isEmpty {
                    rows.append(StoryRowPlan(id: "more-\(clusterID.uuidString)", kind: .moreSources(clusterID: clusterID, count: others.count)))
                    if expanded.contains(clusterID) {
                        for other in others {
                            rows.append(StoryRowPlan(id: other.id.uuidString, kind: .article(id: other.id, caption: nil)))
                        }
                    }
                }
                continue
            }
            rows.append(StoryRowPlan(
                id: story.id.uuidString,
                kind: .article(id: story.id, caption: StoryGrouping.similarCaption(matchedConsumedAt: mark?.matchedConsumedAt, now: now))
            ))
        }
        return rows
    }

    private static func collapsed(_ stories: [StoryListSnap]) -> [StoryListSnap] {
        var order: [String] = []
        var groups: [String: [StoryListSnap]] = [:]
        for story in stories {
            let key = identityKey(story)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(story)
        }
        return order.map { key in
            let items = groups[key] ?? []
            return items.max(by: { score($0) < score($1) }) ?? items[0]
        }
    }

    private static func identityKey(_ story: StoryListSnap) -> String {
        if let videoID = story.videoID, !videoID.isEmpty { return "video:\(videoID)" }
        return ArticleIdentity.libraryKey(url: story.url, guid: story.guid, id: story.id)
    }

    private static func score(_ story: StoryListSnap) -> Int {
        var value = 0
        if story.feedID != nil { value += 8 }
        if story.hasRemoteID { value += 4 }
        if story.stateRaw == "saved" || story.isRemoteStarred { value += 3 }
        if story.stateRaw == "current" { value += 2 }
        return value
    }
}
