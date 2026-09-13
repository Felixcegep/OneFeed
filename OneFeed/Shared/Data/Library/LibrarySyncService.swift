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

    private(set) var status: LibrarySyncStatus = .unlinked
    private(set) var folderDisplayName: String?
    private(set) var lastSyncAt: Date?
    private(set) var lastError: String?
    private(set) var isLinked = false

    private var context: ModelContext?
    private var scopedURL: URL?
    private var libraryFileURL: URL?
    private var isFileBookmark = false
    private var pushTask: Task<Void, Never>?
    private var lastWrittenData: Data?
    private var presenter: LibraryFilePresenter?
    private var isApplyingRemote = false

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

    func configure(with context: ModelContext) {
        self.context = context
        guard !isDisabled else {
            status = .unlinked
            return
        }
        Task { await restoreIfNeeded() }
    }

    func attach(url: URL) async {
        guard !isDisabled else { return }
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
        pushTask?.cancel()
        tearDownAccess()
        LibraryFolderStore.clear()
        folderDisplayName = nil
        lastSyncAt = nil
        lastError = nil
        isLinked = false
        status = .unlinked
    }

    func schedulePush() {
        guard isLinked, !isDisabled, !isApplyingRemote else { return }
        pushTask?.cancel()
        pushTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_500))
            guard !Task.isCancelled else { return }
            await pushNow()
        }
    }

    func syncNow() async {
        guard isLinked else { return }
        await pullAndMerge()
        await pushNow()
    }

    func flush() async {
        pushTask?.cancel()
        guard isLinked else { return }
        await pushNow()
    }

    private var isDisabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-inMemoryStore") || arguments.contains("-uiTesting")
    }

    private func restoreIfNeeded() async {
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
            let local = try LibraryMerge.snapshot(from: context, extraTombstones: LibraryFolderStore.loadTombstones())
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
            let local = try LibraryMerge.snapshot(from: context, extraTombstones: LibraryFolderStore.loadTombstones())
            let merged = LibraryMerge.merge(local: local, remote: remote ?? .empty(), options: options)
            try writeDocument(merged, to: libraryFileURL)
            LibraryFolderStore.saveTombstones(merged.tombstones)
            lastSyncAt = .now
            lastError = nil
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
        lastError = error.localizedDescription
        status = .error(error.localizedDescription)
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
