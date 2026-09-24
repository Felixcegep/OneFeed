import Foundation
import SwiftData

/// Opt-in Gemini pass that replaces a video's preliminary embedding with a short structured summary.
/// It never writes `Article.aiSummary`.
@MainActor
enum SemanticEnrichment {
    static func enrichUpcoming(in context: ModelContext) async {
        guard UserDefaults.standard.bool(forKey: AppPreferenceKey.semanticVideoEnrichment) else { return }
        guard GeminiAPIKeyStore.load() != nil else { return }

        let youtube = "youtube"
        let articles: [Article]
        let memories: [ContentMemory]
        do {
            articles = try context.fetch(FetchDescriptor<Article>(predicate: #Predicate { $0.contentKind == youtube }))
            memories = try context.fetch(FetchDescriptor<ContentMemory>())
        } catch {
            return
        }

        let indexed = index(memories)
        let articlesByKey = articlesByMemoryKey(articles)
        let candidates = articles
            .filter { article in
                guard article.declinedVideoSummary == false else { return false }
                guard hasVideoLocator(article) else { return false }
                guard let memory = memory(for: article, in: indexed) else { return false }
                return needsEnrichment(memory)
            }
            .sorted { $0.publishedAt > $1.publishedAt }
            .prefix(20)

        let client = GeminiClient()
        for article in candidates {
            guard let url = watchURL(for: article) else { continue }
            let parsed: SemanticVideoSummary
            do {
                parsed = try await client.semanticSummary(for: url)
            } catch {
                continue
            }
            guard let memory = memory(for: article, in: indexed) else { continue }

            let vectors = await EmbeddingService().embed(
                title: memory.title,
                body: memory.itemDescription,
                semanticSummary: parsed.compactText,
                languageCode: memory.languageCode
            )

            memory.semanticSummary = parsed.compactText
            memory.summarySource = "gemini"
            memory.semanticText = SemanticText.contentText(
                title: memory.title,
                body: memory.itemDescription,
                semanticSummary: parsed.compactText
            )
            memory.stateRaw = SemanticState.enriched.rawValue

            if let vectors {
                memory.titleVector = ContentVector.pack(vectors.title)
                memory.contentVector = ContentVector.pack(vectors.content)
                memory.embeddingRevision = vectors.revision
                memory.embeddingLanguage = vectors.language
                memory.embeddingDimension = vectors.content.count
                memory.embeddingProvider = "apple-nl"
                memory.stateRaw = SemanticState.final.rawValue
                applyClassification(
                    of: memory,
                    article: article,
                    vectors: vectors,
                    memories: memories,
                    articlesByKey: articlesByKey
                )
            }

            do {
                try context.save()
                NotificationCenter.default.post(name: OneFeedNotify.storyIndexDidChange, object: nil)
            } catch {
                continue
            }
        }
    }

    private static func needsEnrichment(_ memory: ContentMemory) -> Bool {
        if memory.stateRaw == SemanticState.preliminary.rawValue { return true }
        let summary = memory.semanticSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty && memory.stateRaw != SemanticState.final.rawValue
    }

    private static func hasVideoLocator(_ article: Article) -> Bool {
        let videoID = article.videoID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !videoID.isEmpty { return true }
        return article.url != nil
    }

    private static func watchURL(for article: Article) -> URL? {
        if let videoID = article.videoID?.trimmingCharacters(in: .whitespacesAndNewlines),
           let watch = YouTubeProcessor.watchURL(for: videoID) {
            return watch
        }
        return article.url
    }

    private static func index(_ memories: [ContentMemory]) -> [String: ContentMemory] {
        var map: [String: ContentMemory] = [:]
        map.reserveCapacity(memories.count * 2)
        for memory in memories {
            map[memory.identityKey] = memory
            if let externalID = memory.externalID?.trimmingCharacters(in: .whitespacesAndNewlines), !externalID.isEmpty {
                map["video:\(externalID)"] = memory
            }
            if let canonical = memory.canonicalURL?.trimmingCharacters(in: .whitespacesAndNewlines), !canonical.isEmpty {
                let normalized = URL(string: canonical).flatMap(ArticleIdentity.normalizedURLString) ?? canonical
                map["url:\(normalized)"] = memory
            }
        }
        return map
    }

    private static func memory(for article: Article, in index: [String: ContentMemory]) -> ContentMemory? {
        let videoKey = ContentMemory.makeIdentityKey(
            externalID: article.videoID,
            canonicalURL: article.url?.absoluteString
        )
        if let found = index[videoKey] { return found }
        return index[ArticleIdentity.identityKey(for: article)]
    }

    private static func articlesByMemoryKey(_ articles: [Article]) -> [String: Article] {
        var map: [String: Article] = [:]
        for article in articles {
            let videoKey = ContentMemory.makeIdentityKey(
                externalID: article.videoID,
                canonicalURL: article.url?.absoluteString
            )
            map[videoKey] = article
            map[ArticleIdentity.identityKey(for: article)] = article
        }
        return map
    }

    /// `SemanticMemoryPass` has no shared classify helper, so this mirrors its cluster update.
    private static func applyClassification(
        of memory: ContentMemory,
        article: Article,
        vectors: EmbeddingService.EmbeddedVectors,
        memories: [ContentMemory],
        articlesByKey: [String: Article]
    ) {
        let item = semanticItem(
            from: memory,
            sourceTitle: article.feed?.title ?? "",
            titleVector: vectors.title,
            contentVector: vectors.content,
            embeddingLanguage: vectors.language,
            embeddingRevision: vectors.revision,
            hasGeminiSummary: true
        )
        let others = memories.map { other in
            semanticItem(
                from: other,
                sourceTitle: articlesByKey[other.identityKey]?.feed?.title ?? "",
                titleVector: ContentVector.unpack(other.titleVector),
                contentVector: ContentVector.unpack(other.contentVector),
                embeddingLanguage: other.embeddingLanguage,
                embeddingRevision: other.embeddingRevision,
                hasGeminiSummary: other.summarySource == "gemini"
                    && !other.semanticSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
        let verdict = SemanticClassifier.classify(item: item, against: others)
        memory.relationshipRaw = verdict.relationship.rawValue
        memory.confidenceRaw = verdict.confidence.rawValue
        memory.matchedConsumedAt = verdict.matchedConsumedAt
        switch verdict.relationship {
        case .exactDuplicate, .nearDuplicate:
            memory.duplicateOfKey = verdict.matchedIdentityKey
        case .sameStory:
            memory.duplicateOfKey = nil
            let cluster = verdict.storyClusterID ?? UUID()
            memory.storyClusterID = cluster
            if let key = verdict.matchedIdentityKey,
               let match = memories.first(where: { $0.identityKey == key }),
               match.storyClusterID == nil {
                match.storyClusterID = cluster
            }
        case .related, .new:
            memory.duplicateOfKey = nil
            memory.storyClusterID = nil
        }
    }

    private static func semanticItem(
        from memory: ContentMemory,
        sourceTitle: String,
        titleVector: [Double]?,
        contentVector: [Double]?,
        embeddingLanguage: String,
        embeddingRevision: Int,
        hasGeminiSummary: Bool
    ) -> SemanticItem {
        SemanticItem(
            identityKey: memory.identityKey,
            youtubeID: memory.externalID,
            normalizedURL: memory.canonicalURL,
            contentHash: memory.contentHash,
            sourceTitle: sourceTitle,
            publishedAt: memory.publishedAt,
            titleVector: titleVector,
            contentVector: contentVector,
            embeddingLanguage: embeddingLanguage,
            embeddingRevision: embeddingRevision,
            hasGeminiSummary: hasGeminiSummary,
            consumedAt: memory.consumedAt,
            storyClusterID: memory.storyClusterID
        )
    }
}
