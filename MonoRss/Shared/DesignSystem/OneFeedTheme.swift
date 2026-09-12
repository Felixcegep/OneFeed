import SwiftUI
import SwiftData

enum OneFeedTheme {
    /// Warm orange in the NetNewsWire family; used as the app tint, not as a brand copy.
    static let accent = Color(red: 0.89, green: 0.38, blue: 0.16)
    static let page = Color.oneFeedSystemBackground
    static let grouped = Color.oneFeedGroupedBackground
    static let surface = Color.oneFeedSecondaryGroupedBackground
    static let secondarySurface = Color.oneFeedTertiaryFill
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let separator = Color.oneFeedSeparator
    static let radius: CGFloat = 14
    static let cardRadius: CGFloat = 16
    static let pagePadding: CGFloat = 16
    static let thumbnailSize: CGFloat = 72
}

struct PrimaryActionStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(OneFeedTheme.accent.opacity(configuration.isPressed ? 0.78 : 1), in: .rect(cornerRadius: OneFeedTheme.radius))
            .scaleEffect((reduceMotion || !configuration.isPressed) ? 1 : 0.97)
            .animation(reduceMotion ? nil : OneFeedMotion.press, value: configuration.isPressed)
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
            .animation(reduceMotion ? nil : OneFeedMotion.press, value: configuration.isPressed)
    }
}

struct ArticleRow: View {
    let article: Article
    var status: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(article.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(meta)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            if article.imageURL != nil {
                ArticleThumbnail(url: article.imageURL, cornerRadius: 8)
                    .frame(width: OneFeedTheme.thumbnailSize, height: OneFeedTheme.thumbnailSize)
                    .clipped()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this article")
    }

    private var meta: String {
        var parts: [String] = [article.feed?.title ?? "Unknown Source"]
        if let kind = article.kindLabel { parts.append(kind) }
        if let duration = article.timedDurationPhrase { parts.append(duration) }
        parts.append(article.publishedAt.formatted(.dateTime.month(.abbreviated).day()))
        if article.rating > 0 { parts.append(String(repeating: "★", count: article.rating)) }
        if let status { parts.append(status) }
        return parts.joined(separator: " · ")
    }
}

/// Apple News–style lead story for Today.
struct FeaturedStory: View {
    let article: Article

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if article.imageURL != nil {
                ArticleThumbnail(url: article.imageURL, cornerRadius: OneFeedTheme.cardRadius)
                    .frame(maxWidth: .infinity)
                    .frame(height: 210)
                    .clipped()
            }
            Text(article.feed?.title ?? "Source")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OneFeedTheme.accent)
                .lineLimit(1)
            Text(article.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let excerpt = article.displayExcerpt {
                Text(excerpt)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(byline)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens this article")
    }

    private var byline: String {
        var parts = [article.publishedAt.formatted(.relative(presentation: .named))]
        if let duration = article.timedDurationPhrase { parts.append(duration) }
        return parts.joined(separator: " · ")
    }
}

struct ArticleThumbnail: View {
    let url: URL?
    var cornerRadius: CGFloat = 8

    var body: some View {
        Color.clear
            .overlay {
                if let url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .clipped()
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Rectangle()
            .fill(OneFeedTheme.secondarySurface)
            .overlay {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
    }
}

struct OneFeedSectionLabel: View {
    let title: String
    var expanded: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(expanded ? 0 : -90))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct OneFeedGroupCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(OneFeedTheme.surface, in: .rect(cornerRadius: OneFeedTheme.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: OneFeedTheme.cardRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
    }
}

struct FeedDirectoryRow: View {
    let title: String
    var systemImage: String? = nil
    var swatchName: String? = nil
    var count: Int = 0

    var body: some View {
        HStack(spacing: 14) {
            leading
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            UnreadCount(count)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var leading: some View {
        if let swatchName {
            FolderSwatch(name: swatchName)
                .frame(width: 28, alignment: .center)
        } else if let systemImage {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)
        }
    }
}

struct DirectoryRowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect((reduceMotion || !configuration.isPressed) ? 1 : 0.99)
            .animation(reduceMotion ? nil : OneFeedMotion.press, value: configuration.isPressed)
    }
}

struct UnreadCount: View {
    let count: Int

    init(_ count: Int) {
        self.count = count
    }

    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(count) unread")
        }
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

struct ArticleRatingGlyphs: View {
    let rating: Int
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(star <= rating ? Color.primary : Color.secondary.opacity(0.35))
            }
        }
        .accessibilityHidden(true)
    }
}

struct ArticleRatingControl: View {
    let article: Article

    var body: some View {
        if article.isStored {
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        guard article.isStored else { return }
                        article.setRating(article.rating == star ? 0 : star)
                        try? article.modelContext?.save()
                    } label: {
                        Image(systemName: star <= article.rating ? "star.fill" : "star")
                            .font(.body)
                            .foregroundStyle(star <= article.rating ? Color.primary : Color.secondary.opacity(0.38))
                            .frame(width: 36, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                    .accessibilityAddTraits(star <= article.rating ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(article.rating == 0 ? "Rating" : "Rated \(article.rating) of 5")
        }
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

extension View {
    @ViewBuilder
    func articleListRow() -> some View {
        #if os(iOS)
        listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .listRowSeparatorTint(Color.primary.opacity(0.08))
        #else
        listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        #endif
    }

    func articleTimelineList() -> some View {
        listStyle(.plain)
            .contentMargins(.bottom, 12, for: .scrollContent)
    }
}
