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
        _ = try DailyDeckService.generateIfNeeded(in: modelContext)
        _ = try ArticleRetentionService.purge(in: modelContext)
        try persistIfNeeded()
    }

    func setFreshRSSSyncError(accountID: UUID, message: String) throws {
        let matches = try modelContext.fetch(FetchDescriptor<SyncAccount>(predicate: #Predicate { $0.id == accountID }))
        matches.first?.lastSyncError = message
        try persistIfNeeded()
    }
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
