import SwiftUI

extension View {
    /// Keeps the search field immediate and applies the query after a short pause.
    /// Clearing the field applies at once.
    func debouncedSearch(_ text: String, into applied: Binding<String>, delay: Duration = .milliseconds(180)) -> some View {
        modifier(DebouncedSearchModifier(text: text, applied: applied, delay: delay))
    }
}

private struct DebouncedSearchModifier: ViewModifier {
    var text: String
    @Binding var applied: String
    var delay: Duration

    func body(content: Content) -> some View {
        content.task(id: text) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                applied = ""
                return
            }
            if trimmed == applied.trimmingCharacters(in: .whitespacesAndNewlines) {
                return
            }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            applied = text
        }
    }
}
