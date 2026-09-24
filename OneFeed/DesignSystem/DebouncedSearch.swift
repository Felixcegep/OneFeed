import SwiftUI

extension View {
    /// Keeps the search field immediate and applies the query after a short pause.
    /// Clearing the field applies at once.
    func debouncedSearch(_ text: String, into applied: Binding<String>, delay: Duration = .milliseconds(180)) -> some View {
        modifier(DebouncedSearchModifier(text: text, applied: applied, delay: delay))
    }
}

/// Owns the live search field so each keystroke does not rebuild the list.
/// The list updates when the applied query changes, and a cleared field applies at once.
struct OneFeedSearchHost<Content: View>: View {
    @Binding private var applied: String
    private let prompt: String
    private let content: Content
    @State private var text = ""

    init(_ prompt: String, applied: Binding<String>, @ViewBuilder content: () -> Content) {
        self.prompt = prompt
        self._applied = applied
        self.content = content()
    }

    var body: some View {
        content
            .oneFeedSearchable($text, prompt: prompt)
            .debouncedSearch(text, into: $applied)
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
