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

    func finishToday() throws {
        modelContext.autosaveEnabled = false
        _ = try DailyDeckService.generateIfNeeded(in: modelContext, persist: false)
        _ = try ArticleRetentionService.purge(in: modelContext, persist: false)
        try persistIfNeeded()
    }

    func setFreshRSSSyncError(accountID: UUID, message: String) throws {
        let matches = try modelContext.fetch(FetchDescriptor<SyncAccount>(predicate: #Predicate { $0.id == accountID }))
        matches.first?.lastSyncError = message
        try persistIfNeeded()
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
        descriptor.propertiesToFetch = [\.guid, \.url, \.remoteID]
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
