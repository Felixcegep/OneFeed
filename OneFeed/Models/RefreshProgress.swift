import Foundation
import Observation

enum RefreshPhase: Equatable {
    case idle
    case sources
    case sync
    case finishing

    var title: String {
        switch self {
        case .idle: "Idle"
        case .sources: "Updating sources"
        case .sync: "Syncing FreshRSS"
        case .finishing: "Building today"
        }
    }
}

@MainActor
@Observable
final class RefreshProgress {
    private(set) var phase = RefreshPhase.idle
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var currentTitle: String?
    private(set) var articlesFound = 0
    private(set) var estimatedFinish: Date?
    private var lastAdvanceAt: Date?
    private var meanDuration: TimeInterval = 0

    /// Width of the progress line. Moves forward across phase changes and stays put when the refresh ends, so the line can fade out instead of snapping back to empty.
    private(set) var displayedFraction: Double = 0

    var isActive: Bool { phase != .idle }
    var remainingCount: Int { max(0, total - completed) }
    var fraction: Double {
        guard total > 0 else { return phase == .finishing ? 1 : 0 }
        return min(1, Double(completed) / Double(total))
    }

    func begin(phase: RefreshPhase, total: Int, now: Date = .now) {
        let wasIdle = !isActive
        let keepBarFull = !wasIdle && phase == .finishing
        self.phase = phase
        currentTitle = nil
        if wasIdle {
            displayedFraction = 0
            articlesFound = 0
        }
        if keepBarFull {
            self.total = max(1, total)
            completed = self.total
            estimatedFinish = now
            lastAdvanceAt = now
            publishDisplayedFraction()
            return
        }
        if wasIdle {
            self.total = max(0, total)
            completed = 0
            estimatedFinish = nil
            lastAdvanceAt = now
            meanDuration = 0
        } else {
            let carried = completed
            self.total = carried + max(0, total)
            completed = carried
            lastAdvanceAt = now
        }
        publishDisplayedFraction()
    }

    func startItem(title: String) {
        currentTitle = title
    }

    func finishItem(newArticles: Int = 0, now: Date = .now) {
        if let lastAdvanceAt {
            let sample = max(0.05, now.timeIntervalSince(lastAdvanceAt))
            meanDuration = meanDuration == 0 ? sample : (meanDuration * 0.65 + sample * 0.35)
        }
        lastAdvanceAt = now
        completed += 1
        if total < completed { total = completed }
        articlesFound += max(0, newArticles)
        currentTitle = nil
        publishDisplayedFraction()
        let remaining = remainingCount
        if remaining > 0, meanDuration > 0 {
            estimatedFinish = now.addingTimeInterval(meanDuration * Double(remaining))
        } else {
            estimatedFinish = now
        }
    }

    func finish() {
        phase = .idle
        completed = 0
        total = 0
        articlesFound = 0
        currentTitle = nil
        estimatedFinish = nil
        lastAdvanceAt = nil
        meanDuration = 0
    }

    private func publishDisplayedFraction() {
        let next = fraction
        if next > displayedFraction {
            displayedFraction = next
        }
    }

    var primaryText: String { phase.title }

    var countText: String {
        guard total > 0 else { return phase == .finishing ? "Almost done" : "Starting…" }
        return "\(completed) of \(total)"
    }

    var remainingText: String {
        guard total > 0 else { return "" }
        if remainingCount == 0 { return "Last one" }
        return remainingCount == 1 ? "1 left" : "\(remainingCount) left"
    }

    /// Stable line for the full-screen cover. Source names and the countdown change every tick and resize the cover.
    var coverStatus: String {
        guard total > 0 else { return "This can take a minute the first time." }
        return countText
    }

    /// One line for the navigation subtitle so the list does not need a tall banner.
    var compactStatus: String {
        if total > 0 {
            var parts = ["\(completed) of \(total)"]
            if articlesFound > 0 {
                parts.append(articlesFound == 1 ? "1 new" : "\(articlesFound) new")
            }
            return parts.joined(separator: " · ")
        }
        return primaryText
    }

    func detailText(now: Date = .now) -> String {
        var parts: [String] = []
        if let currentTitle, !currentTitle.isEmpty { parts.append(currentTitle) }
        if articlesFound > 0 {
            parts.append(articlesFound == 1 ? "1 new" : "\(articlesFound) new")
        }
        if let eta = Self.remainingPhrase(until: estimatedFinish, now: now) {
            parts.append(eta)
        }
        return parts.joined(separator: " · ")
    }

    func accessibilityText(now: Date = .now) -> String {
        var parts = [primaryText]
        if total > 0 { parts.append("\(completed) of \(total) sources") }
        if articlesFound > 0 { parts.append("\(articlesFound) new articles") }
        if let currentTitle { parts.append("fetching \(currentTitle)") }
        if let eta = Self.remainingPhrase(until: estimatedFinish, now: now) { parts.append(eta) }
        return parts.joined(separator: ", ")
    }

    static func remainingPhrase(until finish: Date?, now: Date) -> String? {
        guard let finish else { return nil }
        let seconds = finish.timeIntervalSince(now)
        if seconds <= 0.5 { return "almost done" }
        if seconds < 8 { return "a few seconds left" }
        if seconds < 60 { return "\(Int(seconds.rounded()))s left" }
        let minutes = max(1, Int((seconds / 60).rounded()))
        return minutes == 1 ? "about 1 min left" : "about \(minutes) min left"
    }
}
