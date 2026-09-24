import Foundation
import SwiftData

/// Preliminary semantic memory. Runs on the ingest actor after articles land and before Today is chosen.
/// Exact copies are recorded without a vector. Embeddings stop after 80 items so a large library cannot stall the deck.
nonisolated enum SemanticMemoryPass {
    private static let embeddingBudget = 80

    static func prepare(in context: ModelContext) async throws {
        let articles = try fetchArticles(in: context)
        let memories = try context.fetch(FetchDescriptor<ContentMemory>())
        let indexed = index(memories)
        let consumed = consumedMarks(for: articles, memories: indexed)
        let jobs = makeJobs(from: articles, memories: indexed)
        var known = semanticItems(from: memories, sourceTitles: sourceTitles(for: articles))
        applyConsumed(consumed, to: &known)

        let embedder = EmbeddingService()
        let outcome = await classify(jobs, against: known, packed: packedVectors(from: memories), embedder: embedder)
        try commit(outcome, consumed: consumed, memories: memories, in: context)
        try context.save()
        NotificationCenter.default.post(name: OneFeedNotify.storyIndexDidChange, object: nil)
    }

    private struct Job: Sendable {
        var identityKey: String
        var youtubeID: String?
        var normalizedURL: String?
        var contentHash: String
        var sourceTitle: String
        var publishedAt: Date
        var title: String
        var body: String
        var languageCode: String
        var semanticText: String
        var sourceType: String
        var itemDescription: String
        var existingStoryClusterID: UUID?
    }

    private struct Decision: Sendable {
        var job: Job
        var relationship: ContentRelationship
        var confidence: SemanticConfidence
        var duplicateOfKey: String?
        var storyClusterID: UUID?
        var matchedConsumedAt: Date?
        var titleVector: [Double]?
        var contentVector: [Double]?
        var embeddingLanguage: String
        var embeddingRevision: Int
        var embedded: Bool
    }

    private struct Outcome: Sendable {
        var decisions: [Decision]
        var clusterPatches: [String: UUID]
    }

    private struct ConsumedMark: Sendable {
        var identityKey: String
        var consumedAt: Date
    }

    private static func fetchArticles(in context: ModelContext) throws -> [Article] {
        var descriptor = FetchDescriptor<Article>()
        // Bodies stay faults until a job is actually embedded. History rows do not need their HTML.
        descriptor.propertiesToFetch = [
            \.id, \.guid, \.title, \.url, \.publishedAt, \.stateRawValue, \.completedAt, \.contentKind, \.videoID, \.remoteID,
        ]
        descriptor.relationshipKeyPathsForPrefetching = [\.feed]
        return try context.fetch(descriptor)
    }

    private static func index(_ memories: [ContentMemory]) -> [String: ContentMemory] {
        var map: [String: ContentMemory] = [:]
        map.reserveCapacity(memories.count)
        for memory in memories {
            map[memory.identityKey] = memory
        }
        return map
    }

    private static func consumedMarks(for articles: [Article], memories: [String: ContentMemory]) -> [ConsumedMark] {
        var marks: [ConsumedMark] = []
        var seen = Set<String>()
        for article in articles where article.state == .read {
            let key = ArticleIdentity.identityKey(for: article)
            guard seen.insert(key).inserted else { continue }
            guard let memory = memories[key], memory.consumedAt == nil else { continue }
            marks.append(ConsumedMark(identityKey: key, consumedAt: article.completedAt ?? .now))
        }
        return marks
    }

    private static func applyConsumed(_ marks: [ConsumedMark], to items: inout [SemanticItem]) {
        let dates = Dictionary(uniqueKeysWithValues: marks.map { ($0.identityKey, $0.consumedAt) })
        for index in items.indices where items[index].consumedAt == nil {
            items[index].consumedAt = dates[items[index].identityKey]
        }
    }

    /// Queued and current rows that still need a decision, newest first, capped so embedding cannot stall Today.
    /// An exact copy already stored stays recorded and does not take another slot.
    private static func makeJobs(from articles: [Article], memories: [String: ContentMemory]) -> [Job] {
        let candidates = articles.filter { article in
            guard article.state == .queued || article.state == .current else { return false }
            return needsPreparation(memories[ArticleIdentity.identityKey(for: article)])
        }
        let ordered = candidates.sorted { $0.publishedAt > $1.publishedAt }
        var seen = Set<String>()
        var jobs: [Job] = []
        jobs.reserveCapacity(min(embeddingBudget, ordered.count))
        for article in ordered {
            let key = ArticleIdentity.identityKey(for: article)
            guard seen.insert(key).inserted else { continue }
            jobs.append(makeJob(for: article, existing: memories[key]))
            if jobs.count == embeddingBudget { break }
        }
        return jobs
    }

    private static func needsPreparation(_ memory: ContentMemory?) -> Bool {
        guard let memory else { return true }
        if memory.relationship == .exactDuplicate { return false }
        let state = memory.stateRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        return state.isEmpty || state == SemanticState.raw.rawValue
    }

    private static func makeJob(for article: Article, existing: ContentMemory?) -> Job {
        let body = plainBody(of: article)
        let title = article.title
        return Job(
            identityKey: ArticleIdentity.identityKey(for: article),
            youtubeID: nonEmpty(article.videoID),
            normalizedURL: ArticleIdentity.normalizedURLString(article.url),
            contentHash: ContentVector.hash(title: title, body: body),
            sourceTitle: article.feed?.title ?? "",
            publishedAt: article.publishedAt,
            title: title,
            body: body,
            languageCode: SemanticText.detectLanguage(title: title, body: body),
            semanticText: SemanticText.contentText(title: title, body: body, semanticSummary: ""),
            sourceType: article.contentKind,
            itemDescription: body,
            existingStoryClusterID: existing?.storyClusterID
        )
    }

    private static func plainBody(of article: Article) -> String {
        let summary = ContentClassifier.stripHTML(article.summary ?? "")
        if !summary.isEmpty { return summary }
        return ContentClassifier.stripHTML(article.contentHTML ?? "")
    }

    private static func sourceTitles(for articles: [Article]) -> [String: String] {
        var titles: [String: String] = [:]
        for article in articles {
            let key = ArticleIdentity.identityKey(for: article)
            let title = article.feed?.title ?? ""
            if titles[key]?.isEmpty != false {
                titles[key] = title
            }
        }
        return titles
    }

    private static func semanticItems(from memories: [ContentMemory], sourceTitles: [String: String]) -> [SemanticItem] {
        memories.map { memory in
            SemanticItem(
                identityKey: memory.identityKey,
                youtubeID: nonEmpty(memory.externalID),
                normalizedURL: memory.canonicalURL,
                contentHash: memory.contentHash,
                sourceTitle: sourceTitles[memory.identityKey] ?? "",
                publishedAt: memory.publishedAt,
                titleVector: nil,
                contentVector: nil,
                embeddingLanguage: memory.embeddingLanguage,
                embeddingRevision: memory.embeddingRevision,
                hasGeminiSummary: !memory.semanticSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                consumedAt: memory.consumedAt,
                storyClusterID: memory.storyClusterID
            )
        }
    }

    private static func packedVectors(from memories: [ContentMemory]) -> [String: (title: Data?, content: Data?)] {
        var packed: [String: (title: Data?, content: Data?)] = [:]
        packed.reserveCapacity(memories.count)
        for memory in memories where memory.titleVector != nil || memory.contentVector != nil {
            packed[memory.identityKey] = (memory.titleVector, memory.contentVector)
        }
        return packed
    }

    /// Unpacks vectors only for the language and revision about to be scored.
    private static func materialize(
        _ known: inout [SemanticItem],
        language: String,
        revision: Int,
        packed: [String: (title: Data?, content: Data?)]
    ) {
        for index in known.indices {
            guard known[index].embeddingLanguage == language,
                  known[index].embeddingRevision == revision,
                  known[index].titleVector == nil,
                  known[index].contentVector == nil,
                  let data = packed[known[index].identityKey] else { continue }
            known[index].titleVector = ContentVector.unpack(data.title)
            known[index].contentVector = ContentVector.unpack(data.content)
        }
    }

    private static func classify(
        _ jobs: [Job],
        against known: [SemanticItem],
        packed: [String: (title: Data?, content: Data?)],
        embedder: EmbeddingService
    ) async -> Outcome {
        var known = known
        var decisions: [Decision] = []
        var patches: [String: UUID] = [:]
        decisions.reserveCapacity(jobs.count)
        for job in jobs {
            let result = await classify(job, against: known, packed: packed, embedder: embedder)
            decisions.append(result.decision)
            if let patch = result.patch {
                patches[patch.key] = patch.id
            }
            known = result.known
        }
        return Outcome(decisions: decisions, clusterPatches: patches)
    }

    private static func classify(
        _ job: Job,
        against known: [SemanticItem],
        packed: [String: (title: Data?, content: Data?)],
        embedder: EmbeddingService
    ) async -> (decision: Decision, known: [SemanticItem], patch: (key: String, id: UUID)?) {
        var known = known
        var item = SemanticItem(
            identityKey: job.identityKey,
            youtubeID: job.youtubeID,
            normalizedURL: job.normalizedURL,
            contentHash: job.contentHash,
            sourceTitle: job.sourceTitle,
            publishedAt: job.publishedAt,
            titleVector: nil,
            contentVector: nil,
            embeddingLanguage: "",
            embeddingRevision: 0,
            hasGeminiSummary: false,
            consumedAt: nil,
            storyClusterID: job.existingStoryClusterID
        )
        let exact = SemanticClassifier.classify(item: item, against: known)
        var verdict = exact
        var embedded = false
        if exact.relationship != .exactDuplicate {
            let vectors = await embedder.embed(
                title: job.title,
                body: job.body,
                semanticSummary: "",
                languageCode: job.languageCode
            )
            if let vectors {
                embedded = true
                item.titleVector = vectors.title
                item.contentVector = vectors.content
                item.embeddingLanguage = vectors.language
                item.embeddingRevision = vectors.revision
                materialize(&known, language: vectors.language, revision: vectors.revision, packed: packed)
                let comparable = known.filter { memory in
                    hasVectors(memory)
                        && memory.embeddingLanguage == vectors.language
                        && memory.embeddingRevision == vectors.revision
                }
                verdict = SemanticClassifier.classify(item: item, against: comparable)
            }
        }

        var patch: (key: String, id: UUID)?
        var storyClusterID: UUID?
        var duplicateOfKey: String?
        switch verdict.relationship {
        case .exactDuplicate, .nearDuplicate:
            duplicateOfKey = verdict.matchedIdentityKey
            storyClusterID = job.existingStoryClusterID
        case .sameStory:
            let cluster = verdict.storyClusterID ?? UUID()
            storyClusterID = cluster
            item.storyClusterID = cluster
            if let matchKey = verdict.matchedIdentityKey,
               let index = known.firstIndex(where: { $0.identityKey == matchKey }),
               known[index].storyClusterID == nil {
                known[index].storyClusterID = cluster
                patch = (matchKey, cluster)
            }
        case .new, .related:
            storyClusterID = nil
            item.storyClusterID = nil
        }
        if item.storyClusterID == nil, let index = known.firstIndex(where: { $0.identityKey == item.identityKey }) {
            item.storyClusterID = known[index].storyClusterID
        }
        remember(item, in: &known)

        let decision = Decision(
            job: job,
            relationship: verdict.relationship,
            confidence: verdict.confidence,
            duplicateOfKey: duplicateOfKey,
            storyClusterID: storyClusterID,
            matchedConsumedAt: verdict.matchedConsumedAt,
            titleVector: item.titleVector,
            contentVector: item.contentVector,
            embeddingLanguage: item.embeddingLanguage,
            embeddingRevision: item.embeddingRevision,
            embedded: embedded
        )
        return (decision, known, patch)
    }

    private static func hasVectors(_ item: SemanticItem) -> Bool {
        item.titleVector?.isEmpty == false || item.contentVector?.isEmpty == false
    }

    private static func remember(_ item: SemanticItem, in known: inout [SemanticItem]) {
        if let index = known.firstIndex(where: { $0.identityKey == item.identityKey }) {
            known[index] = item
        } else {
            known.append(item)
        }
    }

    private static func commit(
        _ outcome: Outcome,
        consumed: [ConsumedMark],
        memories: [ContentMemory],
        in context: ModelContext
    ) throws {
        var indexed = index(memories)
        for mark in consumed {
            guard let memory = indexed[mark.identityKey], memory.consumedAt == nil else { continue }
            memory.consumedAt = mark.consumedAt
        }
        for decision in outcome.decisions {
            let memory = indexed[decision.job.identityKey] ?? insertMemory(for: decision, in: context, index: &indexed)
            fill(memory, with: decision)
        }
        for (key, cluster) in outcome.clusterPatches {
            guard let memory = indexed[key], memory.storyClusterID == nil else { continue }
            memory.storyClusterID = cluster
        }
    }

    private static func insertMemory(
        for decision: Decision,
        in context: ModelContext,
        index: inout [String: ContentMemory]
    ) -> ContentMemory {
        let memory = ContentMemory(identityKey: decision.job.identityKey, title: decision.job.title)
        context.insert(memory)
        index[decision.job.identityKey] = memory
        return memory
    }

    private static func fill(_ memory: ContentMemory, with decision: Decision) {
        let job = decision.job
        memory.canonicalURL = job.normalizedURL
        memory.externalID = job.youtubeID
        memory.sourceType = job.sourceType
        memory.publishedAt = job.publishedAt
        memory.title = job.title
        memory.itemDescription = job.itemDescription
        memory.languageCode = job.languageCode
        memory.semanticText = job.semanticText
        if memory.semanticSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            memory.semanticSummary = ""
        }
        memory.summarySource = "rss"
        memory.contentHash = job.contentHash
        memory.relationship = decision.relationship
        memory.confidence = decision.confidence
        memory.matchedConsumedAt = decision.matchedConsumedAt
        memory.duplicateOfKey = decision.duplicateOfKey

        if decision.embedded {
            memory.titleVector = ContentVector.pack(decision.titleVector ?? [])
            memory.contentVector = ContentVector.pack(decision.contentVector ?? [])
            memory.embeddingProvider = "apple-nl"
            memory.embeddingLanguage = decision.embeddingLanguage
            memory.embeddingRevision = decision.embeddingRevision
            memory.embeddingDimension = decision.contentVector?.count ?? decision.titleVector?.count ?? 0
            memory.state = .preliminary
        } else {
            memory.state = .raw
        }

        switch decision.relationship {
        case .exactDuplicate, .nearDuplicate:
            if memory.storyClusterID == nil {
                memory.storyClusterID = decision.storyClusterID
            }
        case .sameStory:
            memory.storyClusterID = decision.storyClusterID
        case .new, .related:
            memory.storyClusterID = nil
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
