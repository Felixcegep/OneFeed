import SwiftData
import SwiftUI

/// One reversible Skip or Not interested. A later action replaces it.
@MainActor
@Observable
final class ReadingUndoCenter {
    static let shared = ReadingUndoCenter()

    private(set) var offer: Offer?
    var undoError: String?
    private var dismissTask: Task<Void, Never>?

    struct Offer: Identifiable {
        let id = UUID()
        var title: String
        var strongerTitle: String?
        let undo: () -> Bool
        var stronger: (() -> Bool)?
    }

    func present(
        title: String,
        strongerTitle: String? = nil,
        stronger: (() -> Bool)? = nil,
        undo: @escaping () -> Bool
    ) {
        dismissTask?.cancel()
        let shown = Offer(
            title: title,
            strongerTitle: strongerTitle,
            undo: undo,
            stronger: stronger
        )
        offer = shown
        scheduleDismiss(of: shown.id)
    }

    @discardableResult
    func performUndo() -> Bool {
        guard let current = offer else { return false }
        guard current.undo() else {
            undoError = String(localized: "Couldn’t put that story back.")
            scheduleDismiss(of: current.id)
            return false
        }
        offer = nil
        dismissTask?.cancel()
        return true
    }

    /// Skip can become Not interested. Undo still restores the story from before the skip.
    @discardableResult
    func performStronger() -> Bool {
        guard let current = offer, let action = current.stronger else { return false }
        guard action() else {
            undoError = String(localized: "Couldn’t file that as not interested.")
            scheduleDismiss(of: current.id)
            return false
        }
        guard var updated = offer else { return true }
        updated.stronger = nil
        updated.strongerTitle = nil
        updated.title = String(localized: "Not interested")
        offer = updated
        scheduleDismiss(of: updated.id)
        return true
    }

    private func scheduleDismiss(of id: UUID) {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            if offer?.id == id {
                offer = nil
            }
        }
    }
}

@MainActor
enum ReadingUndo {
    private struct FinishSnapshot {
        let articleID: UUID
        let stateRaw: String
        let completedAt: Date?
        let notInterested: Bool
        let firstDisplayedAt: Date?
        let isRemoteStarred: Bool
        let deckItemID: UUID?
        let deckStatusRaw: String?
        let promotedItemID: UUID?
        let promotedStatusRaw: String?
        let promotedArticleID: UUID?
        let promotedStateRaw: String?
        let promotedCompletedAt: Date?
        let promotedFirstDisplayedAt: Date?
        let promotedRemoteStarred: Bool?
        let remoteID: String?
        /// Pending mutation ids for `remoteID` before this action.
        let pendingMutationIDs: [UUID]
        /// markRead rows already pending at begin. A missing id at undo means it flushed.
        let pendingMarkReadIDs: [UUID]
        /// markRead rows this action inserted. Filled in `commit`.
        var addedMarkReadIDs: [UUID]
    }

    private static var stagedID: UUID?
    private static var staged: FinishSnapshot?

    /// Call before the article changes. A second call for the same article keeps the first snapshot,
    /// so Not interested can be recorded after the snapshot and still undo cleanly.
    static func begin(_ article: Article, in context: ModelContext) {
        if stagedID == article.id { return }
        stagedID = article.id
        staged = capture(article, in: context)
    }

    static func commit(_ article: Article, in context: ModelContext) {
        var snapshot = consume(for: article, in: context)
        if let remoteID = snapshot.remoteID {
            let kept = Set(snapshot.pendingMutationIDs)
            snapshot.addedMarkReadIDs = pendingMutations(remoteID: remoteID, in: context)
                .filter { $0.kind == .markRead && !kept.contains($0.id) }
                .map(\.id)
        }
        let marked = article.notInterested && !snapshot.notInterested
        let articleID = article.id
        let stronger: (() -> Bool)? = marked ? nil : {
            guard let article = storedArticle(id: articleID, in: context) else { return false }
            do {
                try NotInterestedLog.record(article, in: context)
                return true
            } catch {
                return false
            }
        }
        ReadingUndoCenter.shared.present(
            title: marked ? String(localized: "Not interested") : String(localized: "Skipped"),
            strongerTitle: marked ? nil : String(localized: "Not interested"),
            stronger: stronger
        ) {
            do {
                try restore(snapshot, in: context)
                return true
            } catch {
                context.rollback()
                return false
            }
        }
    }

    private static func consume(for article: Article, in context: ModelContext) -> FinishSnapshot {
        if stagedID == article.id, let staged {
            self.staged = nil
            stagedID = nil
            return staged
        }
        staged = nil
        stagedID = nil
        return capture(article, in: context)
    }

    private static func capture(_ article: Article, in context: ModelContext) -> FinishSnapshot {
        var deckItemID: UUID?
        var deckStatusRaw: String?
        var promotedItemID: UUID?
        var promotedStatusRaw: String?
        var promotedArticleID: UUID?
        var promotedStateRaw: String?
        var promotedCompletedAt: Date?
        var promotedFirstDisplayedAt: Date?
        var promotedRemoteStarred: Bool?
        let remoteID = article.remoteID
        let pending = remoteID.map { pendingMutations(remoteID: $0, in: context) } ?? []
        if let deck = try? DailyDeckService().todayDeck(in: context),
           let item = deck.items.first(where: { $0.resolvedArticleID() == article.id }) {
            deckItemID = item.id
            deckStatusRaw = item.statusRawValue
            if item.status == .current {
                let next = deck.items
                    .filter { $0.status == .queued && $0.articleExists(in: context) }
                    .sorted { $0.position < $1.position }
                    .first
                promotedItemID = next?.id
                promotedStatusRaw = next?.statusRawValue
                if let id = next?.resolvedArticleID(), let nextArticle = DailyDeckService.lightweightArticle(id: id, in: context) {
                    promotedArticleID = nextArticle.id
                    promotedStateRaw = nextArticle.stateRawValue
                    promotedCompletedAt = nextArticle.completedAt
                    promotedFirstDisplayedAt = nextArticle.firstDisplayedAt
                    promotedRemoteStarred = nextArticle.isRemoteStarred
                }
            }
        }
        return FinishSnapshot(
            articleID: article.id,
            stateRaw: article.stateRawValue,
            completedAt: article.completedAt,
            notInterested: article.notInterested,
            firstDisplayedAt: article.firstDisplayedAt,
            isRemoteStarred: article.isRemoteStarred,
            deckItemID: deckItemID,
            deckStatusRaw: deckStatusRaw,
            promotedItemID: promotedItemID,
            promotedStatusRaw: promotedStatusRaw,
            promotedArticleID: promotedArticleID,
            promotedStateRaw: promotedStateRaw,
            promotedCompletedAt: promotedCompletedAt,
            promotedFirstDisplayedAt: promotedFirstDisplayedAt,
            promotedRemoteStarred: promotedRemoteStarred,
            remoteID: remoteID,
            pendingMutationIDs: pending.map(\.id),
            pendingMarkReadIDs: pending.filter { $0.kind == .markRead }.map(\.id),
            addedMarkReadIDs: []
        )
    }

    private static func restore(_ snapshot: FinishSnapshot, in context: ModelContext) throws {
        guard let article = storedArticle(id: snapshot.articleID, in: context) else { return }
        article.stateRawValue = snapshot.stateRaw
        article.completedAt = snapshot.completedAt
        article.notInterested = snapshot.notInterested
        article.firstDisplayedAt = snapshot.firstDisplayedAt
        article.isRemoteStarred = snapshot.isRemoteStarred
        if !snapshot.notInterested {
            removeNotInterestedEntry(for: article, in: context)
        }
        if let itemID = snapshot.deckItemID, let status = snapshot.deckStatusRaw {
            deckItem(id: itemID, in: context)?.statusRawValue = status
        }
        if let itemID = snapshot.promotedItemID, let status = snapshot.promotedStatusRaw {
            deckItem(id: itemID, in: context)?.statusRawValue = status
        }
        collapseExtraCurrentDeckItems(snapshot, in: context)
        if let promotedID = snapshot.promotedArticleID,
           let promoted = storedArticle(id: promotedID, in: context),
           let state = snapshot.promotedStateRaw {
            promoted.stateRawValue = state
            promoted.completedAt = snapshot.promotedCompletedAt
            promoted.firstDisplayedAt = snapshot.promotedFirstDisplayedAt
            if let starred = snapshot.promotedRemoteStarred {
                promoted.isRemoteStarred = starred
            }
            LibraryChange.note(promoted)
        }
        LibraryChange.note(article)
        reconcileRemoteQueue(snapshot, article: article, in: context)
        try context.save()
        let current = (try? DailyDeckService().currentItem(in: context))?.article
        WidgetSnapshotStore.write(article: current ?? article)
    }

    /// Restoring the skipped item to current must not leave the promoted row current as well.
    private static func collapseExtraCurrentDeckItems(_ snapshot: FinishSnapshot, in context: ModelContext) {
        guard snapshot.deckStatusRaw == ArticleState.current.rawValue,
              let keptID = snapshot.deckItemID,
              let kept = deckItem(id: keptID, in: context) else { return }
        for other in kept.deck?.items ?? [] where other.id != keptID && other.status == .current {
            if other.id == snapshot.promotedItemID,
               snapshot.promotedStatusRaw == ArticleState.current.rawValue {
                continue
            }
            other.status = .queued
        }
    }

    /// Deletes mutations this action added. If a markRead already flushed and the story returns to unread, queue markUnread.
    private static func reconcileRemoteQueue(_ snapshot: FinishSnapshot, article: Article, in context: ModelContext) {
        guard let remoteID = article.remoteID else { return }
        let pending = pendingMutations(remoteID: remoteID, in: context)
        let watchedMarkRead = snapshot.pendingMarkReadIDs + snapshot.addedMarkReadIDs
        let hadMarkRead = !watchedMarkRead.isEmpty
        let markReadStillPending = pending.contains { $0.kind == .markRead }
        FreshRSSSyncService().cancelPendingMutations(
            forRemoteID: remoteID,
            keeping: Set(snapshot.pendingMutationIDs),
            in: context
        )
        let restored = ArticleState(rawValue: snapshot.stateRaw)
        let returnsToUnread = restored == .queued || restored == .current
        guard hadMarkRead, !markReadStillPending, returnsToUnread else { return }
        FreshRSSSyncService().enqueueCompensatingUnread(for: article, in: context)
    }

    private static func pendingMutations(remoteID: String, in context: ModelContext) -> [PendingSyncMutation] {
        let remoteID = remoteID
        let descriptor = FetchDescriptor<PendingSyncMutation>(
            predicate: #Predicate { $0.remoteArticleID == remoteID }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func storedArticle(id: UUID, in context: ModelContext) -> Article? {
        var descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func deckItem(id: UUID, in context: ModelContext) -> DailyDeckItem? {
        var descriptor = FetchDescriptor<DailyDeckItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func removeNotInterestedEntry(for article: Article, in context: ModelContext) {
        for entry in NotInterestedLog.entries(matching: article, in: context) {
            context.delete(entry)
        }
    }
}

struct ReadingUndoBanner: ViewModifier {
    var onApplied: () -> Void = {}
    @State private var center = ReadingUndoCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ZStack {
                    if let offer = center.offer {
                        bar(offer)
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : OneFeedMotion.overlay, value: center.offer?.id)
                .onChange(of: undoAnnouncement) { _, message in
                    guard !message.isEmpty else { return }
                    AccessibilityNotification.Announcement(message).post()
                }
            }
            .alert("Couldn’t update that story", isPresented: Binding(
                get: { center.undoError != nil },
                set: { if !$0 { center.undoError = nil } }
            )) {
                Button("OK", role: .cancel) { center.undoError = nil }
            } message: {
                Text(center.undoError ?? "")
            }
    }

    private var undoAnnouncement: String {
        guard let offer = center.offer else { return "" }
        if let strongerTitle = offer.strongerTitle {
            return "\(offer.title). Undo, or \(strongerTitle)."
        }
        return "\(offer.title). Undo available."
    }

    private func bar(_ offer: ReadingUndoCenter.Offer) -> some View {
        let title = Text(offer.title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(OneFeedTheme.ink)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .fixedSize(horizontal: false, vertical: true)
        let actions = HStack(spacing: 8) {
            if let strongerTitle = offer.strongerTitle {
                Button(strongerTitle) {
                    if center.performStronger() {
                        onApplied()
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OneFeedTheme.ink)
                .frame(minHeight: 44)
                .accessibilityHint("Files this story as not interested. Undo still puts it back.")
            }
            Button("Undo") {
                if center.performUndo() {
                    onApplied()
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(OneFeedTheme.plaster)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(OneFeedTheme.ink, in: Capsule())
            .accessibilityHint("Puts the story back")
        }
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    title
                    actions
                }
            } else {
                HStack(spacing: 12) {
                    title
                    Spacer(minLength: 8)
                    actions
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            OneFeedTheme.paper
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(OneFeedTheme.sand)
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityElement(children: .contain)
    }
}

extension View {
    func readingUndoBanner(onApplied: @escaping () -> Void = {}) -> some View {
        modifier(ReadingUndoBanner(onApplied: onApplied))
    }
}
