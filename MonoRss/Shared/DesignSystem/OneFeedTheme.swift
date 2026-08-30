import SwiftUI

enum OneFeedTheme {
    static let accent = Color(red: 0.85, green: 0.42, blue: 0.20)
    static let page = Color(uiColor: .systemBackground)
    static let grouped = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let secondarySurface = Color(uiColor: .tertiarySystemFill)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let separator = Color(uiColor: .separator)
    static let radius: CGFloat = 16
    static let pagePadding: CGFloat = 22
}

struct PrimaryActionStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color(uiColor: .systemBackground))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.primary.opacity(configuration.isPressed ? 0.76 : 1))
            .clipShape(.rect(cornerRadius: OneFeedTheme.radius))
            .scaleEffect((reduceMotion || !configuration.isPressed) ? 1 : 0.97)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct DecisionActionStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(OneFeedTheme.secondarySurface)
            .clipShape(.rect(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect((reduceMotion || !configuration.isPressed) ? 1 : 0.97)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct ArticleRow: View {
    let article: Article
    var status: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(article.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            HStack(spacing: 5) {
                Text(article.feed?.title ?? "Unknown Source")
                Text("·")
                Text(article.publishedAt, format: .dateTime.month(.abbreviated).day())
                Text("·")
                Text("\(article.estimatedReadingMinutes) min")
                if let status {
                    Spacer(minLength: 8)
                    Text(status)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(OneFeedTheme.secondarySurface, in: Capsule())
                        .accessibilityLabel(status)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
