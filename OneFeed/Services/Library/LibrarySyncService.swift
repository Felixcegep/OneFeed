import Foundation
import Observation
import SwiftData
import UniformTypeIdentifiers

enum LibrarySyncStatus: Equatable, Sendable {
    case unlinked
    case idle
    case syncing
    case waitingForDownload
    case error(String)
}

@MainActor
@Observable
final class LibrarySyncService {
    static let shared = LibrarySyncService()

    enum Request: Equatable, Sendable {
        /// Push or pull when unambiguous. Never overwrite either side on conflict.
        case automatic
        /// Same as automatic, but a conflict is reported to Settings.
        case manual
        case keepThisIPhone
        case useCloudFile
    }

    enum Outcome: Equatable, Sendable {
        case unlinked
        case inSync
        case pushed
        case pulled
        case conflict
        case skippedActiveSession
        case failed(String)
    }

    private(set) var status: LibrarySyncStatus = .unlinked
    private(set) var folderDisplayName: String?
    private(set) var lastSyncAt: Date?
    private(set) var lastError: String?
    private(set) var isLinked = false
    private(set) var isSyncing = false
    private(set) var lastOutcome: Outcome = .unlinked
    private(set) var lastErrorMessage: String?
    private(set) var linkedRecord: CloudFileLinkRecord?

    /// Reader presented. Automatic and manual pulls wait; `useCloudFile` still pulls.
    var hasActiveReadingSession = false

    private var context: ModelContext?
    private var scopedURL: URL?
    private var libraryFileURL: URL?
    private var isFileBookmark = false
    private var pushTask: Task<Void, Never>?
    /// A library change arrived while a sync was already writing. One push runs after that sync.
    private var pushAgain = false
    private var lastWrittenData: Data?
    private var presenter: LibraryFilePresenter?
    private var isApplyingRemote = false
    private var hasScheduledRestore = false

    private let defaults: UserDefaults
    private let linkStore: CloudFileLinkStore
    private let fileManager: FileManager
    private let googleDrive: (any GoogleDriveAPIClienting)?

    var footerText: String {
        switch status {
        case .unlinked:
            return "Keep subscriptions and reading state in a folder on iCloud Drive or Google Drive. iPhone and Mac share the same OneFeed.library.json file."
        case .waitingForDownload:
            return "Waiting for iCloud to download OneFeed.library.json."
        case .error(let message):
            return message
        case .syncing:
            return "Updating the shared library file…"
        case .idle:
            if let lastSyncAt {
                return "Last updated \(lastSyncAt.formatted(date: .abbreviated, time: .shortened))."
            }
            return "This device is using the shared library file."
        }
    }

    var isAutoSyncEnabled: Bool {
        guard isLinked else { return false }
        if let linkedRecord, linkedRecord.usesGoogleDriveAPI {
            return linkedRecord.syncMode == .automatic
        }
        return true
    }

    private var usesGoogleDriveAPI: Bool {
        (linkedRecord ?? linkStore.load())?.usesGoogleDriveAPI == true
    }

    private var resolvedGoogleDrive: any GoogleDriveAPIClienting {
        googleDrive ?? GoogleDriveAPIClient.shared
    }

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        googleDrive: (any GoogleDriveAPIClienting)? = nil
    ) {
        self.defaults = defaults
        self.linkStore = CloudFileLinkStore(defaults: defaults)
        self.fileManager = fileManager
        self.googleDrive = googleDrive
        linkedRecord = linkStore.load()
        if let linkedRecord, linkedRecord.usesGoogleDriveAPI {
            isLinked = true
            folderDisplayName = linkedRecord.displayName
            lastSyncAt = linkedRecord.lastSyncedAt
            status = .idle
        } else if linkedRecord == nil {
            lastOutcome = .unlinked
        }
    }

    func configure(with context: ModelContext) {
        self.context = context
        guard !isDisabled else {
            status = .unlinked
            isLinked = false
            return
        }
        guard !hasScheduledRestore else { return }
        hasScheduledRestore = true
        Task { await restoreIfNeeded() }
    }

    func attach(url: URL) async {
        guard !isDisabled else { return }
        clearDriveLink(signOut: true)
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = values.isDirectory ?? url.hasDirectoryPath
            let isFile = !isDirectory
            try LibraryFolderStore.saveBookmark(for: url, isFile: isFile)
            await restoreIfNeeded()
            await pullAndMerge()
            await pushNow()
        } catch {
            present(error)
        }
    }

    func detach() {
        unlink()
    }

    func unlink() {
        pushTask?.cancel()
        tearDownAccess()
        LibraryFolderStore.clear()
        clearDriveLink(signOut: true)
        folderDisplayName = nil
        lastSyncAt = nil
        lastError = nil
        lastErrorMessage = nil
        lastOutcome = .unlinked
        isLinked = false
        isSyncing = false
        pushAgain = false
        status = .unlinked
    }

    func setSyncMode(_ mode: CloudFileSyncMode) {
        guard var record = linkedRecord ?? linkStore.load() else { return }
        record.syncMode = mode
        persist(record)
    }

    /// Remembers the Drive file. Does not OAuth, find, create, or sync.
    func linkGoogleDrive(
        fileID: String,
        displayName: String,
        accountEmail: String?,
        lastSyncedHash: String? = nil
    ) {
        guard !isDisabled else { return }
        tearDownAccess()
        LibraryFolderStore.clear()
        let record = CloudFileLinkRecord(
            bookmarkData: Data(),
            displayName: displayName,
            locationKind: .googleDrive,
            lastSyncedHash: lastSyncedHash,
            lastSyncedAt: lastSyncedHash == nil ? nil : .now,
            googleDriveFileID: fileID,
            googleDriveAccountEmail: accountEmail
        )
        persist(record)
        lastError = nil
        lastErrorMessage = nil
        isLinked = true
        status = .idle
        if lastSyncedHash != nil {
            lastOutcome = .pushed
        }
    }

    func schedulePush() {
        guard isLinked, !isDisabled, !isApplyingRemote else { return }
        if usesGoogleDriveAPI {
            guard isAutoSyncEnabled else { return }
            pushTask?.cancel()
            pushTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1_500))
                guard !Task.isCancelled else { return }
                if isSyncing {
                    pushAgain = true
                    return
                }
                _ = await sync(request: .automatic)
            }
            return
        }
        pushTask?.cancel()
        pushTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_500))
            guard !Task.isCancelled else { return }
            if isSyncing {
                pushAgain = true
                return
            }
            await pushNow()
        }
    }

    /// Runs one delayed push after the sync that was already in progress.
    private func resumeDeferredPush() {
        guard pushAgain else { return }
        pushAgain = false
        schedulePush()
    }

    func syncNow() async {
        guard isLinked, !isSyncing else { return }
        if usesGoogleDriveAPI {
            _ = await sync(request: .manual)
            return
        }
        isSyncing = true
        defer {
            isSyncing = false
            resumeDeferredPush()
        }
        await pullAndMerge()
        await pushNow()
    }

    func flush() async {
        pushTask?.cancel()
        guard isLinked else { return }
        if isSyncing {
            pushAgain = true
            return
        }
        if usesGoogleDriveAPI {
            guard isAutoSyncEnabled else { return }
            _ = await sync(request: .automatic)
            return
        }
        isSyncing = true
        defer {
            isSyncing = false
            resumeDeferredPush()
        }
        await pushNow()
    }

    func sync(request: Request) async -> Outcome {
        guard isSyncing == false else { return lastOutcome }
        guard !isDisabled else {
            lastOutcome = .unlinked
            return .unlinked
        }
        guard linkStore.load()?.usesGoogleDriveAPI == true else {
            lastOutcome = .unlinked
            return .unlinked
        }

        isSyncing = true
        status = .syncing
        defer {
            isSyncing = false
            resumeDeferredPush()
        }

        do {
            let outcome = try await performDriveSync(request: request)
            lastOutcome = outcome
            lastError = nil
            lastErrorMessage = nil
            status = outcome == .unlinked ? .unlinked : .idle
            return outcome
        } catch {
            present(error)
            return lastOutcome
        }
    }

    /// SHA-256 of `LibraryDocument.encoded()` bytes. Drive `md5Checksum` is never used.
    static func encodedLibraryFile(from context: ModelContext) throws -> Data {
        var document = try LibraryMerge.snapshot(
            from: context,
            extraTombstones: LibraryFolderStore.loadTombstones()
        )
        document.updatedAt = portableUpdatedAt(for: document)
        return try document.encoded()
    }

    private var isDisabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-inMemoryStore") || arguments.contains("-uiTesting")
    }

    private func restoreIfNeeded() async {
        if let record = linkStore.load(), record.usesGoogleDriveAPI {
            tearDownAccess()
            persist(record)
            isLinked = true
            status = .idle
            return
        }
        if googleDrive != nil {
            status = isLinked ? .idle : .unlinked
            return
        }

        do {
            guard let resolved = try LibraryFolderStore.resolvedURL() else {
                status = .unlinked
                isLinked = false
                return
            }
            if resolved.isStale {
                try LibraryFolderStore.saveBookmark(for: resolved.url, isFile: resolved.isFile)
            }
            tearDownAccess()
            scopedURL = resolved.url
            isFileBookmark = resolved.isFile
            _ = resolved.url.startAccessingSecurityScopedResource()
            libraryFileURL = LibraryFolderStore.libraryFileURL(from: resolved.url, isFile: resolved.isFile)
            folderDisplayName = LibraryFolderStore.storedDisplayName() ?? LibraryFolderStore.displayName(for: resolved.url)
            isLinked = true
            status = .idle
            startPresenting()
        } catch {
            present(error)
        }
    }

    private func performDriveSync(request: Request) async throws -> Outcome {
        guard var record = linkStore.load(), record.usesGoogleDriveAPI else { return .unlinked }
        guard let context else {
            throw GoogleDriveAPIError.httpFailure(
                status: 0,
                message: String(localized: "The library is not ready.")
            )
        }

        let localData = try await SwiftDataIngest.actor(from: context).encodedLibraryFile(
            extraTombstones: LibraryFolderStore.loadTombstones()
        )
        let localHash = CloudFileContentHash.sha256Hex(localData)

        let remoteData = try await readDriveData(from: record)
        let remoteHash = remoteData.map(CloudFileContentHash.sha256Hex)

        var decision = CloudFileReconciler.decide(
            localHash: localHash,
            remoteHash: remoteHash,
            lastSyncedHash: record.lastSyncedHash
        )

        switch request {
        case .keepThisIPhone:
            decision = .push
        case .useCloudFile:
            decision = .pull
        case .automatic, .manual:
            break
        }

        switch decision {
        case .inSync:
            record.lastSyncedHash = localHash
            record.lastSyncedAt = .now
            persist(record)
            return .inSync
        case .push:
            try await writeDrive(localData, to: record)
            record.lastSyncedHash = localHash
            record.lastSyncedAt = .now
            persist(record)
            return .pushed
        case .pull:
            guard let remoteData else {
                try await writeDrive(localData, to: record)
                record.lastSyncedHash = localHash
                record.lastSyncedAt = .now
                persist(record)
                return .pushed
            }
            if hasActiveReadingSession, request == .automatic || request == .manual {
                return .skippedActiveSession
            }
            return try pullDrive(
                remoteData,
                hash: CloudFileContentHash.sha256Hex(remoteData),
                into: context,
                record: record
            )
        case .conflict:
            return .conflict
        }
    }

    private func readDriveData(from record: CloudFileLinkRecord) async throws -> Data? {
        guard let fileID = record.googleDriveFileID, fileID.isEmpty == false else { return nil }
        do {
            let data = try await resolvedGoogleDrive.downloadFile(id: fileID)
            return data.isEmpty ? nil : data
        } catch {
            if Self.isMissingRemoteFile(error) {
                return nil
            }
            throw error
        }
    }

    private func writeDrive(_ data: Data, to record: CloudFileLinkRecord) async throws {
        guard let fileID = record.googleDriveFileID, fileID.isEmpty == false else {
            throw GoogleDriveAPIError.httpFailure(
                status: 0,
                message: String(localized: "The Google Drive library file could not be saved.")
            )
        }
        try await resolvedGoogleDrive.uploadFile(id: fileID, data: data)
    }

    private static func isMissingRemoteFile(_ error: Error) -> Bool {
        if let apiError = error as? GoogleDriveAPIError,
           case .httpFailure(let status, _) = apiError {
            return status == 404
        }
        if let urlError = error as? URLError {
            return urlError.code == .fileDoesNotExist
        }
        return false
    }

    private func pullDrive(
        _ remoteData: Data,
        hash: String,
        into context: ModelContext,
        record: CloudFileLinkRecord
    ) throws -> Outcome {
        let document = try LibraryDocument.decode(remoteData)
        writeRecoveryCopy(of: context)
        isApplyingRemote = true
        defer { isApplyingRemote = false }
        _ = try LibraryMerge.apply(document, to: context, options: .all)
        if (try? DailyDeckService().todayDeck(in: context)) == nil {
            _ = try DailyDeckService().generateIfNeeded(in: context)
        } else {
            _ = try ArticleQueueService().ensureCurrent(in: context)
        }
        try LibraryMerge.applyCurrent(document, to: context)
        try context.save()
        LibraryFolderStore.saveTombstones(document.tombstones)
        var updated = record
        updated.lastSyncedHash = hash
        updated.lastSyncedAt = .now
        persist(updated)
        return .pulled
    }

    private func writeRecoveryCopy(of context: ModelContext) {
        do {
            let data = try Self.encodedLibraryFile(from: context)
            let directory = try recoveryDirectory()
            try data.write(
                to: directory.appendingPathComponent("OneFeed.library-before-pull.json"),
                options: .atomic
            )
        } catch {
            return
        }
    }

    private func recoveryDirectory() throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent("LibraryRecovery", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func persist(_ record: CloudFileLinkRecord) {
        linkStore.save(record)
        linkedRecord = record
        lastSyncAt = record.lastSyncedAt
        folderDisplayName = record.displayName
        isLinked = record.usesGoogleDriveAPI || isLinked
    }

    private func clearDriveLink(signOut: Bool) {
        let shouldSignOut = signOut && (linkedRecord ?? linkStore.load())?.usesGoogleDriveAPI == true
        linkStore.clear()
        linkedRecord = nil
        lastOutcome = .unlinked
        if shouldSignOut {
            GoogleDriveOAuthClient.shared.signOut()
        }
    }

    nonisolated static func portableUpdatedAt(for document: LibraryDocument) -> Date {
        var latest = document.currentUpdatedAt ?? Date(timeIntervalSince1970: 0)
        for feed in document.feeds {
            latest = max(latest, feed.updatedAt)
        }
        for article in document.articles {
            latest = max(latest, article.updatedAt)
        }
        for tombstone in document.tombstones {
            latest = max(latest, tombstone.deletedAt)
        }
        return latest
    }

    private func pullAndMerge() async {
        guard let context, let libraryFileURL, isLinked else { return }
        status = .syncing
        do {
            if try needsDownload(libraryFileURL) {
                status = .waitingForDownload
                return
            }
            let remote = try readDocument(at: libraryFileURL)
            let options = mergeOptions(in: context)
            isApplyingRemote = true
            defer { isApplyingRemote = false }
            let local = try await SwiftDataIngest.actor(from: context).librarySnapshot(
                extraTombstones: LibraryFolderStore.loadTombstones()
            )
            let merged = LibraryMerge.merge(local: local, remote: remote ?? .empty(), options: options)
            _ = try LibraryMerge.apply(merged, to: context, options: options)
            if (try? DailyDeckService().todayDeck(in: context)) == nil {
                _ = try DailyDeckService().generateIfNeeded(in: context)
            } else {
                _ = try ArticleQueueService().ensureCurrent(in: context)
            }
            try LibraryMerge.applyCurrent(merged, to: context)
            try context.save()
            try writeDocument(merged, to: libraryFileURL)
            LibraryFolderStore.saveTombstones(merged.tombstones)
            lastSyncAt = .now
            lastError = nil
            lastErrorMessage = nil
            status = .idle
        } catch {
            present(error)
        }
    }

    private func pushNow() async {
        guard let context, let libraryFileURL, isLinked else { return }
        status = .syncing
        do {
            if try needsDownload(libraryFileURL) {
                status = .waitingForDownload
                return
            }
            let remote = try readDocument(at: libraryFileURL)
            let options = mergeOptions(in: context)
            let local = try await SwiftDataIngest.actor(from: context).librarySnapshot(
                extraTombstones: LibraryFolderStore.loadTombstones()
            )
            let merged = LibraryMerge.merge(local: local, remote: remote ?? .empty(), options: options)
            try writeDocument(merged, to: libraryFileURL)
            LibraryFolderStore.saveTombstones(merged.tombstones)
            lastSyncAt = .now
            lastError = nil
            lastErrorMessage = nil
            status = .idle
        } catch {
            present(error)
        }
    }

    private func mergeOptions(in context: ModelContext) -> LibraryMergeOptions {
        let freshRSS = SyncProvider.freshRSS.rawValue
        let enabled = (try? context.fetch(
            FetchDescriptor<SyncAccount>(predicate: #Predicate { $0.providerRawValue == freshRSS && $0.isEnabled })
        ))?.first != nil
        return .forAccount(freshRSSEnabled: enabled)
    }

    private func needsDownload(_ url: URL) throws -> Bool {
        guard FileManager.default.isUbiquitousItem(at: url) else { return false }
        let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        if values.ubiquitousItemDownloadingStatus == .current { return false }
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
        return true
    }

    private func readDocument(at url: URL) throws -> LibraryDocument? {
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var result: Result<LibraryDocument?, Error>?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
            do {
                if LibraryFolderStore.isConflictCopy(readURL) {
                    result = .success(nil)
                    return
                }
                guard FileManager.default.fileExists(atPath: readURL.path) else {
                    result = .success(nil)
                    return
                }
                let data = try Data(contentsOf: readURL)
                lastWrittenData = data
                result = .success(try LibraryDocument.decode(data))
            } catch {
                result = .failure(error)
            }
        }
        if let coordinatorError { throw coordinatorError }
        switch result {
        case .success(let document): return document
        case .failure(let error): throw error
        case nil: return nil
        }
    }

    private func writeDocument(_ document: LibraryDocument, to url: URL) throws {
        let data = try document.encoded()
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var writeError: Error?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { writeURL in
            do {
                try FileManager.default.createDirectory(
                    at: writeURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: writeURL, options: [.atomic])
                lastWrittenData = data
            } catch {
                writeError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let writeError { throw writeError }
    }

    private func startPresenting() {
        guard let libraryFileURL else { return }
        if let presenter {
            NSFileCoordinator.removeFilePresenter(presenter)
        }
        let presenter = LibraryFilePresenter(url: libraryFileURL) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                await self.handlePresentedChange()
            }
        }
        self.presenter = presenter
        NSFileCoordinator.addFilePresenter(presenter)
    }

    private func handlePresentedChange() async {
        guard let libraryFileURL, !isApplyingRemote else { return }
        do {
            let data = try Data(contentsOf: libraryFileURL)
            if data == lastWrittenData { return }
        } catch {
            return
        }
        await pullAndMerge()
    }

    private func tearDownAccess() {
        if let presenter {
            NSFileCoordinator.removeFilePresenter(presenter)
            self.presenter = nil
        }
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        libraryFileURL = nil
    }

    private func present(_ error: Error) {
        guard UserFacingFailure.shouldSurface(error) else {
            lastError = nil
            lastErrorMessage = nil
            lastOutcome = .failed("Couldn’t sync the library.")
            if case .unlinked = status {
                return
            }
            status = .idle
            return
        }
        let message = UserFacingFailure.message(for: error, fallback: "Couldn’t sync the library.")
        lastError = message
        lastErrorMessage = message
        lastOutcome = .failed(message)
        status = .error(message)
    }
}

private final class LibraryFilePresenter: NSObject, NSFilePresenter {
    var presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    private let onChange: () -> Void

    init(url: URL, onChange: @escaping () -> Void) {
        self.presentedItemURL = url
        self.onChange = onChange
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
        presentedItemOperationQueue.qualityOfService = .utility
    }

    func presentedItemDidChange() {
        onChange()
    }

    func presentedItemDidMove(to newURL: URL) {
        presentedItemURL = newURL
        onChange()
    }
}

enum LibraryDocumentPicker {
    static var folderTypes: [UTType] { [.folder] }
    static var fileTypes: [UTType] { [.json, .data] }
}
