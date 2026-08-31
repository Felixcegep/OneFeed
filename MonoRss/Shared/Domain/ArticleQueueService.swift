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
            for duplicate in currents.dropFirst() { duplicate.state = .queued; duplicate.firstDisplayedAt = nil }
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
        if selected != nil { try context.save() }
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
        try context.save()
        _ = try ensureCurrent(in: context)
    }

    func restoreSaved(_ article: Article, in context: ModelContext) throws {
        article.state = .queued
        article.completedAt = nil
        article.isRemoteStarred = false
        try context.save()
        _ = try ensureCurrent(in: context)
    }
}
