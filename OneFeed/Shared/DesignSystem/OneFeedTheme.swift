import SwiftUI
import SwiftData

enum OneFeedTheme {
    /// House pigment — held in reserve, like Hermès orange or Acne cobalt. The mark and wall labels only.
    static let accent = Color(red: 0.82, green: 0.33, blue: 0.14)
    static let plaster = Color.oneFeedPlaster
    static let page = Color.oneFeedPlaster
    static let paper = Color.oneFeedPlaster
    static let grouped = Color.oneFeedPlaster
    static let surface = Color.oneFeedSecondaryGroupedBackground
    static let secondarySurface = Color.oneFeedTertiaryFill
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let separator = Color.primary.opacity(0.12)
    /// Photograph crop, not a card. COS / Acne use near-zero radius.
    static let radius: CGFloat = 2
    static let cardRadius: CGFloat = 2
    static let pagePadding: CGFloat = 22
    static let thumbnailWidth: CGFloat = 64
    static let thumbnailHeight: CGFloat = 86
    static let thumbnailSize: CGFloat = 72
    static let featuredHeight: CGFloat = 340
    static let readerCorner: CGFloat = 4
    static let readerWidth: CGFloat = 760
    static let readerHeight: CGFloat = 720
}

/// Museum wall label: tiny, tracked, uppercase.
struct GalleryLabel: View {
    let text: String
    var pigment = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .tracking(1.8)
            .textCase(.uppercase)
            .foregroundStyle(pigment ? OneFeedTheme.accent : Color.secondary)
            .lineLimit(1)
    }
}

struct PrimaryActionStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .tracking(1.4)
            .foregroundStyle(OneFeedTheme.plaster)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.primary.opacity(configuration.isPressed ? 0.72 : 1), in: Rectangle())
            .scaleEffect((reduceMotion || !configuration.isPressed) ? 1 : 0.99)
            .animation(reduceMotion ? nil : OneFeedMotion.press, value: configuration.isPressed)
    }
}

struct DecisionActionStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .tracking(0.6)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.clear)
            .overlay {
                Rectangle().strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(reduceMotion ? nil : OneFeedMotion.press, value: configuration.isPressed)
    }
}

struct ArticleRow: View {
    let article: Article
    var status: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ArticleThumbnail(url: article.imageURL, cornerRadius: OneFeedTheme.radius)
                .frame(width: OneFeedTheme.thumbnailWidth, height: OneFeedTheme.thumbnailHeight)
                .clipped()

            VStack(alignment: .leading, spacing: 7) {
                GalleryLabel(text: article.feed?.title ?? "Source", pigment: true)
                Text(article.title)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(meta)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this article")
    }

    private var meta: String {
        var parts: [String] = []
        if let kind = article.kindLabel { parts.append(kind) }
        if let duration = article.timedDurationPhrase { parts.append(duration) }
        parts.append(article.publishedAt.formatted(.dateTime.month(.abbreviated).day()))
        if article.rating > 0 { parts.append(String(repeating: "★", count: article.rating)) }
        if let status { parts.append(status) }
        return parts.joined(separator: "  ·  ")
    }
}

/// Lookbook hero — full-bleed crop, then a wall label. The photograph is the work.
struct FeaturedStory: View {
    let article: Article

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if article.imageURL != nil {
                ArticleThumbnail(url: article.imageURL, cornerRadius: OneFeedTheme.radius)
                    .frame(maxWidth: .infinity)
                    .frame(height: OneFeedTheme.featuredHeight)
                    .clipped()
            }

            VStack(alignment: .leading, spacing: 10) {
                GalleryLabel(text: article.feed?.title ?? "Source", pigment: true)
                Text(article.title)
                    .font(.system(.title, design: .serif))
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
                GalleryLabel(text: byline)
            }
            .padding(.horizontal, OneFeedTheme.pagePadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens this article")
    }

    private var byline: String {
        var parts = [article.publishedAt.formatted(.dateTime.month(.abbreviated).day().year())]
        if let duration = article.timedDurationPhrase { parts.append(duration) }
        return parts.joined(separator: "  ·  ")
    }
}

struct ArticleThumbnail: View {
    let url: URL?
    var cornerRadius: CGFloat = 2

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
            .fill(Color.primary.opacity(0.05))
    }
}

struct OneFeedSectionLabel: View {
    let title: String
    var expanded: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            GalleryLabel(text: title)
            Spacer(minLength: 8)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .medium))
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
            .overlay {
                Rectangle()
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
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
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            UnreadCount(count)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var leading: some View {
        if let swatchName {
            FolderSwatch(name: swatchName)
                .frame(width: 16, alignment: .center)
        } else if let systemImage {
            Image(systemName: systemImage)
                .font(.body.weight(.regular))
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
        }
    }
}

struct DirectoryRowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
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
                .font(.system(size: 13, weight: .regular).monospacedDigit())
                .tracking(0.8)
                .foregroundStyle(.tertiary)
                .contentTransition(.numericText())
                .accessibilityLabel("\(count) unread")
        }
    }
}

struct FolderSwatch: View {
    let name: String

    var body: some View {
        Rectangle()
            .fill(tint)
            .frame(width: 2, height: 16)
            .accessibilityHidden(true)
    }

    /// Muted textile samples — ochre, oxblood, forest, slate, sand, ink.
    private var tint: Color {
        let palette: [Color] = [
            Color(red: 0.72, green: 0.48, blue: 0.28),
            Color(red: 0.45, green: 0.16, blue: 0.16),
            Color(red: 0.22, green: 0.36, blue: 0.28),
            Color(red: 0.28, green: 0.32, blue: 0.38),
            Color(red: 0.62, green: 0.56, blue: 0.44),
            Color(red: 0.18, green: 0.17, blue: 0.16)
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
        let _ = systemImage
        ContentUnavailableView {
            VStack(spacing: 22) {
                OneFeedMark(size: 40)
                Text(title)
                    .font(.system(.title2, design: .serif))
            }
        } description: {
            Text(description)
                .font(.body)
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
        listRowInsets(EdgeInsets(top: 14, leading: 22, bottom: 14, trailing: 22))
            .listRowSeparatorTint(Color.primary.opacity(0.1))
            .listRowBackground(OneFeedTheme.plaster)
        #else
        listRowInsets(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24))
            .listRowBackground(OneFeedTheme.plaster)
        #endif
    }

    func articleTimelineList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(OneFeedTheme.plaster)
            .contentMargins(.bottom, 28, for: .scrollContent)
            .oneFeedScrollEdge()
    }
}
