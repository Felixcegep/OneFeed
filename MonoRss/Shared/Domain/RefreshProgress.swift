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

    var isActive: Bool { phase != .idle }
    var remainingCount: Int { max(0, total - completed) }
    var fraction: Double {
        guard total > 0 else { return phase == .finishing ? 1 : 0 }
        return min(1, Double(completed) / Double(total))
    }

    func begin(phase: RefreshPhase, total: Int, now: Date = .now) {
        self.phase = phase
        self.total = max(0, total)
        completed = 0
        currentTitle = nil
        if phase == .sources {
            articlesFound = 0
        }
        estimatedFinish = nil
        lastAdvanceAt = now
        meanDuration = 0
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
