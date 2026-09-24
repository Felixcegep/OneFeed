import Foundation
import SwiftData

@MainActor
struct ArticleQueueService {
    @discardableResult
    func ensureCurrent(in context: ModelContext, lastDisplayedFeedID: UUID? = nil) throws -> Article? {
        let currentValue = ArticleState.current.rawValue
        var currentDescriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.stateRawValue == currentValue })
        currentDescriptor.sortBy = [SortDescriptor(\.firstDisplayedAt, order: .forward)]
        let currents = try context.fetch(currentDescriptor)
        if let current = currents.first {
            for duplicate in currents.dropFirst() {
                duplicate.state = .queued
                duplicate.firstDisplayedAt = nil
                LibraryChange.note(duplicate)
            }
            if currents.count > 1 { try context.save() }
            WidgetSnapshotStore.write(article: current)
            return current
        }

        let queuedValue = ArticleState.queued.rawValue
        var descriptor = FetchDescriptor<Article>(predicate: #Predicate {
            $0.stateRawValue == queuedValue && ($0.feed?.isEnabled ?? false)
        })
        descriptor.sortBy = [SortDescriptor(\.publishedAt, order: .forward)]
        let candidates = try context.fetch(descriptor)
        let selected = candidates.first(where: { $0.feed?.id != lastDisplayedFeedID }) ?? candidates.first
        selected?.state = .current
        selected?.firstDisplayedAt = .now
        if let selected {
            LibraryChange.note(selected)
            try context.save()
        }
        WidgetSnapshotStore.write(article: selected)
        return selected
    }

    @discardableResult
    func transition(
        _ article: Article,
        to state: ArticleState,
        in context: ModelContext
    ) throws -> Article? {
        precondition([.read, .skipped, .saved].contains(state), "Current can only leave through a terminal action")
        let previousFeedID = article.feed?.id
        article.state = state
        article.completedAt = .now
        if state == .saved { article.isRemoteStarred = true }
        LibraryChange.note(article)
        try context.save()
        return try ensureCurrent(in: context, lastDisplayedFeedID: previousFeedID)
    }

    func complete(_ article: Article, as state: ArticleState, in context: ModelContext) throws {
        if article.state == .current {
            _ = try transition(article, to: state, in: context)
            return
        }
        precondition([.read, .skipped, .saved].contains(state), "Browse completion must be a terminal action")
        article.state = state
        article.completedAt = .now
        if state == .saved { article.isRemoteStarred = true }
        LibraryChange.note(article)
        try context.save()
        _ = try ensureCurrent(in: context)
    }

    func restoreSaved(_ article: Article, in context: ModelContext) throws {
        article.state = .queued
        article.completedAt = nil
        article.isRemoteStarred = false
        LibraryChange.note(article)
        try context.save()
        _ = try ensureCurrent(in: context)
    }

    /// Moves a finished article into Queue (`.saved`). Rating and the reading takeaway stay.
    func moveToQueue(_ article: Article, in context: ModelContext) throws {
        let clearedNotInterested = article.notInterested
        if clearedNotInterested {
            article.notInterested = false
            try deleteNotInterestedEntries(matching: article, in: context)
        }
        guard article.state != .saved else {
            if clearedNotInterested {
                LibraryChange.note(article)
                try context.save()
            }
            return
        }
        article.state = .saved
        article.isRemoteStarred = true
        if article.completedAt == nil {
            article.completedAt = .now
        }
        try parkOnTodayDeck(article, in: context)
        LibraryChange.note(article)
        FreshRSSSyncService().enqueueMutation(for: article, transition: .saved, in: context)
        try context.save()
    }

    private func deleteNotInterestedEntries(matching article: Article, in context: ModelContext) throws {
        for entry in NotInterestedLog.entries(matching: article, in: context) {
            context.delete(entry)
        }
    }

    /// Saved deck items leave Today. A current item promotes the next queued item, the same way `DailyDeckService.advance` does.
    private func parkOnTodayDeck(_ article: Article, in context: ModelContext) throws {
        guard let deck = try DailyDeckService().todayDeck(in: context) else { return }
        let matches = deck.items.filter { $0.article?.id == article.id }
        guard !matches.isEmpty else { return }

        let wasCurrent = matches.contains { $0.status == .current }
        for match in matches {
            match.status = .saved
        }
        guard wasCurrent else { return }

        let nextItem = deck.items
            .filter { $0.status == .queued && $0.article?.id != article.id }
            .sorted { $0.position < $1.position }
            .first
        if let nextItem {
            nextItem.status = .current
            if let promoted = nextItem.article {
                promoted.state = .current
                promoted.firstDisplayedAt = .now
                LibraryChange.note(promoted)
            }
        }
        WidgetSnapshotStore.write(article: nextItem?.article)
    }
}
