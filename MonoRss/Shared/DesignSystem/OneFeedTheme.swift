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
    static let cardRadius: CGFloat = 20
    static let pagePadding: CGFloat = 20
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

struct ArticleCard: View {
    let article: Article
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                FolderSwatch(name: article.feed?.folderName ?? article.feed?.title ?? "Source")
                Text(article.feed?.title ?? "Source")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(article.estimatedReadingMinutes) min")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            Text(article.title)
                .font(compact ? .headline : .title3.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(compact ? 3 : 4)
            if !compact, let excerpt = article.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !excerpt.isEmpty {
                Text(excerpt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Text(article.publishedAt, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(compact ? 14 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OneFeedTheme.surface, in: .rect(cornerRadius: OneFeedTheme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: OneFeedTheme.cardRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens this article")
    }
}

struct FolderSwatch: View {
    let name: String

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(tint.gradient)
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }

    private var tint: Color {
        let palette: [Color] = [
            Color(red: 0.91, green: 0.45, blue: 0.27),
            Color(red: 0.27, green: 0.51, blue: 0.86),
            Color(red: 0.31, green: 0.68, blue: 0.47),
            Color(red: 0.62, green: 0.42, blue: 0.78),
            Color(red: 0.95, green: 0.64, blue: 0.22),
            Color(red: 0.22, green: 0.64, blue: 0.70)
        ]
        let index = abs(name.hashValue) % palette.count
        return palette[index]
    }
}

struct EmptyLibraryState: View {
    let title: String
    let systemImage: String
    let description: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(description)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
    }
}
