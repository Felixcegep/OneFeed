import Foundation
import SwiftData

/// Owns a SwiftData context on a background executor. Inserts and `save()`
/// stay off the main thread so Feed / Queue `@Query` are not rebuilt mid-write.
@ModelActor
actor LibraryIngestActor {
    func persistIfNeeded() throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }

    func finishToday() async throws {
        modelContext.autosaveEnabled = false
        try await SemanticMemoryPass.prepare(in: modelContext)
        _ = try DailyDeckService.generateIfNeeded(in: modelContext, persist: false)
        _ = try ArticleRetentionService.purge(in: modelContext, persist: false)
        try persistIfNeeded()
    }

    func setFreshRSSSyncError(accountID: UUID, message: String) throws {
        let matches = try modelContext.fetch(FetchDescriptor<SyncAccount>(predicate: #Predicate { $0.id == accountID }))
        matches.first?.lastSyncError = message
        try persistIfNeeded()
    }

    /// Full-text the current story and the next few. The download and the body write stay on this actor.
    func enrichUpcomingArticles(
        currentItemID: UUID?,
        extraQueued: Int,
        session: URLSession = .shared,
        extractor: any ArticleExtracting = SwiftReadabilityExtractor()
    ) async {
        modelContext.autosaveEnabled = false
        guard let deck = try? DailyDeckService.todayDeck(in: modelContext) else { return }
        let items = deck.items.sorted { $0.position < $1.position }
        let start = currentItemID.flatMap { id in items.first { $0.id == id }?.position }
            ?? items.first { $0.status == .current }?.position
            ?? 0
        let policy = ArticleExtractionPolicy()
        var bodies: [ExtractedBody] = []
        for item in items.filter({ $0.position >= start }).prefix(1 + extraQueued) {
            guard let articleID = item.resolvedArticleID() else { continue }
            guard ArticleExtractionService.shouldFetchStoredArticle(id: articleID, policy: policy, in: modelContext.container) else { continue }
            guard let url = DailyDeckService.lightweightArticle(id: articleID, in: modelContext)?.url else { continue }
            guard let html = await ArticleExtractionService.downloadedArticle(
                url: url,
                session: session,
                extractor: extractor
            ) else { continue }
            let minutes = ContentClassifier.readingMinutes(words: ContentClassifier.wordCount(in: html))
            bodies.append(ExtractedBody(articleID: articleID, html: html, estimatedMinutes: minutes))
        }
        try? persistExtractedBodies(bodies)
    }

    func persistExtractedBodies(_ bodies: [ExtractedBody]) throws {
        guard !bodies.isEmpty else { return }
        for body in bodies {
            let articleID = body.articleID
            let matches = try modelContext.fetch(FetchDescriptor<Article>(predicate: #Predicate { $0.id == articleID }))
            guard let article = matches.first else { continue }
            article.contentHTML = body.html
            if body.estimatedMinutes > article.estimatedReadingMinutes {
                article.estimatedReadingMinutes = body.estimatedMinutes
            }
        }
        try persistIfNeeded()
    }

    func importOPML(_ outlines: [OPMLFeedOutline]) throws -> (newSources: Int, folderMembershipsAdded: Int) {
        modelContext.autosaveEnabled = false
        return try OPMLImport.apply(outlines, in: modelContext)
    }

    func encodedLibraryFile(extraTombstones: [LibraryTombstone]) throws -> Data {
        try librarySnapshot(extraTombstones: extraTombstones).encoded()
    }

    func librarySnapshot(extraTombstones: [LibraryTombstone]) throws -> LibraryDocument {
        var document = try LibraryMerge.snapshot(from: modelContext, extraTombstones: extraTombstones)
        document.updatedAt = LibrarySyncService.portableUpdatedAt(for: document)
        return document
    }

    func identityArticles() -> [Article] {
        var descriptor: FetchDescriptor<Article>
        if let cutoff = ArticleRetentionService.ingestCutoff(isFirstPopulate: false) {
            let saved = ArticleState.saved.rawValue
            descriptor = FetchDescriptor(predicate: #Predicate { article in
                article.publishedAt >= cutoff || article.stateRawValue == saved || article.isRemoteStarred
            })
        } else {
            descriptor = FetchDescriptor<Article>()
        }
        // Every field the index and a later sync update, except the article body.
        descriptor.propertiesToFetch = [
            \.id, \.guid, \.title, \.url, \.author, \.publishedAt, \.summary,
            \.estimatedReadingMinutes, \.stateRawValue, \.remoteID, \.isRemoteStarred,
            \.contentKind, \.durationSeconds, \.videoID,
        ]
        descriptor.relationshipKeyPathsForPrefetching = [\.feed]
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}

nonisolated struct ExtractedBody: Sendable {
    let articleID: UUID
    let html: String
    let estimatedMinutes: Int
}

/// Hops progress UI back to the main actor without taking the ingest context with it.
nonisolated struct RefreshProgressSink: Sendable {
    nonisolated(unsafe) private let progress: RefreshProgress?

    init(_ progress: RefreshProgress?) {
        self.progress = progress
    }

    func begin(phase: RefreshPhase, total: Int) async {
        guard let progress else { return }
        await progress.begin(phase: phase, total: total)
    }

    func finishItem(newArticles: Int) async {
        guard let progress else { return }
        await progress.finishItem(newArticles: newArticles)
    }
}

enum SwiftDataIngest {
    @MainActor
    static func actor(from viewContext: ModelContext) throws -> LibraryIngestActor {
        if viewContext.hasChanges {
            try viewContext.save()
        }
        return LibraryIngestActor(modelContainer: viewContext.container)
    }
}
