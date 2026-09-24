import SwiftUI
import SwiftData

enum OneFeedTheme {
    /// Attention — mark, save verb, sparse chrome. Not titles, body, or rules.
    static let accent = Color.oneFeedAttention
    static let accentPressed = OneFeedPalette.attentionPressed.color
    static let accentSoft = OneFeedPalette.attentionSoft.color
    /// Sage for Done. Attention stays the Save verb.
    static let sage = Color.oneFeedSaved
    static let saved = Color.oneFeedSaved
    static let error = Color.oneFeedErrorText
    static let destructive = Color.oneFeedErrorText
    static let link = Color.oneFeedLink
    static let attention = Color.oneFeedAttention
    static let clinical = Color.oneFeedClinical
    static let research = Color.oneFeedResearch
    static let wellness = Color.oneFeedWellness
    /// Current wash. Pair with weight, a leading bar, or a label — never color alone.
    static let current = Color.oneFeedCurrent

    static let plaster = Color.oneFeedPlaster
    static let page = Color.oneFeedPlaster
    static let paper = Color.oneFeedPaper
    static let warm1 = Color.oneFeedWarm1
    static let grouped = Color.oneFeedPlaster
    static let surface = Color.oneFeedPaper
    static let secondarySurface = Color.oneFeedWarm1
    static let ink = Color.oneFeedInk
    static let graphite = Color.oneFeedGraphite
    static let stone = Color.oneFeedStone
    static let sand = Color.oneFeedSand
    static let primaryText = Color.oneFeedInk
    static let secondaryText = Color.oneFeedGraphite
    static let separator = Color.oneFeedSand

    static let radiusHairline: CGFloat = 4
    static let radius: CGFloat = 10
    static let cardRadius: CGFloat = 12
    static let radiusPill: CGFloat = 18
    static let radiusCapsule: CGFloat = 24
    static let pagePadding: CGFloat = 20
    static let thumbnailWidth: CGFloat = 56
    static let thumbnailHeight: CGFloat = 56
    static let thumbnailSize: CGFloat = 56
    static let featuredHeight: CGFloat = 248
    static let readerCorner: CGFloat = 10
    static let readerWidth: CGFloat = 760
    static let readerHeight: CGFloat = 720
    /// Centered measure for Mac lists and featured cards. UX23: 680–760.
    static let readingColumnWidth: CGFloat = 720
    static let formColumnWidth: CGFloat = 520

    /// Authored display — system New York serif.
    static func serifDisplay(_ size: CGFloat = 32) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    /// Article prose. Pair with ~1.55 line height in the reader.
    static func serifBody(_ size: CGFloat = 16) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    /// Chrome and row titles — SF Pro.
    static func sansUI(_ size: CGFloat = 15, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

/// Point-size fonts ignore Bold Text. Semantic styles already follow it.
private struct OneFeedLegibleWeight: ViewModifier {
    @Environment(\.legibilityWeight) private var legibilityWeight

    func body(content: Content) -> some View {
        if legibilityWeight == .bold {
            content.fontWeight(.semibold)
        } else {
            content
        }
    }
}

extension View {
    func oneFeedLegibleWeight() -> some View {
        modifier(OneFeedLegibleWeight())
    }
}

/// Editorial labels: compact, scalable, and readable against paper or plaster.
struct GalleryLabel: View {
    let text: String
    var pigment = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .tracking(0.4)
            .textCase(.uppercase)
            .foregroundStyle(pigment ? OneFeedTheme.accent : OneFeedTheme.graphite)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Section title. Native section spacing supplies the separation between groups.
struct GallerySectionHeader: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(OneFeedTheme.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            #if os(macOS)
            .padding(.top, 12)
            #else
            .padding(.top, 4)
            #endif
            .padding(.bottom, 8)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Side-by-side at standard sizes; stacked when Dynamic Type needs the full width.
struct StackedLabeledValue: View {
    let title: String
    let value: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(value)
                    .foregroundStyle(OneFeedTheme.graphite)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        } else {
            LabeledContent(title, value: value)
        }
    }
}

/// Ink fill, cream type, capsule. Press scales to 0.97 — no offset shadow.
struct PrimaryActionStyle: ButtonStyle {
    var expands = true
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(OneFeedTheme.plaster)
            .padding(.horizontal, expands ? 0 : 22)
            .frame(maxWidth: expands ? .infinity : nil, minHeight: 50)
            .background(OneFeedTheme.ink.opacity(isEnabled ? 1 : 0.35), in: Capsule())
            .scaleEffect((reduceMotion || !configuration.isPressed) ? 1 : 0.97)
            .animation(reduceMotion ? nil : OneFeedMotion.press, value: configuration.isPressed)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.55), trigger: configuration.isPressed) { _, pressed in
                pressed
            }
    }
}

/// Compact ink capsule for the reader Done verb.
struct InkCapsuleStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(OneFeedTheme.plaster)
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(OneFeedTheme.ink, in: Capsule())
            .scaleEffect((reduceMotion || !configuration.isPressed) ? 1 : 0.97)
            .animation(reduceMotion ? nil : OneFeedMotion.press, value: configuration.isPressed)
    }
}

/// Paper fill, 1pt sand, radius 10. Compact when `expands` is false.
struct DecisionActionStyle: ButtonStyle {
    var expands = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(OneFeedTheme.ink)
            .padding(.horizontal, expands ? 0 : 14)
            .frame(maxWidth: expands ? .infinity : nil, minHeight: 44)
            .background(
                OneFeedTheme.paper,
                in: RoundedRectangle(cornerRadius: OneFeedTheme.radius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: OneFeedTheme.radius, style: .continuous)
                    .strokeBorder(OneFeedTheme.sand, lineWidth: 1)
            }
            .scaleEffect((reduceMotion || !configuration.isPressed) ? 1 : 0.97)
            .animation(reduceMotion ? nil : OneFeedMotion.press, value: configuration.isPressed)
    }
}

/// Display-only attribution for subscribed stories and standalone saved links.
enum ArticlePresentation {
    static func sourceName(for article: Article) -> String {
        if let title = article.feed?.title.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if let host = article.url?.host(),
           let scheme = article.url?.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return host
        }
        if article.contentKind == "epub" {
            if let author = article.author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
                return author
            }
            return String(localized: "EPUB")
        }
        if article.contentKind == "pdf" {
            return String(localized: "PDF")
        }
        return String(localized: "Saved link")
    }
}

struct ArticleRow: View {
    let article: Article
    var status: String? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var imageFailed = false

    private var isCurrent: Bool { article.isCurrentReading }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                if let currentReadingLabel = article.currentReadingLabel {
                    Text(currentReadingLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(OneFeedTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(article.title)
                    .font(isCurrent ? .headline.weight(.bold) : .headline)
                    .foregroundStyle(OneFeedTheme.ink)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Group {
                    Text(ArticlePresentation.sourceName(for: article))
                        .font(.subheadline)
                        .foregroundStyle(OneFeedTheme.graphite)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(meta)
                    .font(.caption)
                    .foregroundStyle(OneFeedTheme.graphite)
                    .fixedSize(horizontal: false, vertical: true)
                if let status {
                    Text(status)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(OneFeedTheme.graphite)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let takeaway = article.readingTakeawayLine {
                    Text(takeaway)
                        .font(.subheadline)
                        .foregroundStyle(OneFeedTheme.ink)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            if let url = article.displayImageURL, !dynamicTypeSize.isAccessibilitySize {
                if imageFailed {
                    thumbnailPlaceholder
                } else {
                    ArticleThumbnail(url: url, cornerRadius: OneFeedTheme.radius) {
                        imageFailed = true
                    }
                    .frame(width: 64, height: 64)
                    .clipped()
                }
            }
        }
        .padding(.leading, isCurrent ? 10 : 0)
        .overlay(alignment: .leading) {
            if isCurrent {
                Capsule()
                    .fill(OneFeedTheme.ink)
                    .frame(width: 3, height: 22)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityHint("Opens this article")
        .onChange(of: article.imageURL) { _, _ in
            imageFailed = false
        }
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: OneFeedTheme.radius, style: .continuous)
            .fill(OneFeedTheme.warm1)
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)
    }

    private var meta: String {
        var parts: [String] = []
        if let kind = article.kindLabel { parts.append(kind) }
        if let duration = article.timedDurationPhrase { parts.append(duration) }
        parts.append(OneFeedDateLabel.monthAndDay(article.publishedAt))
        if article.rating > 0 { parts.append(String(repeating: "★", count: article.rating)) }
        return parts.joined(separator: "  ·  ")
    }
}

/// Photograph on paper, then authored serif. The crop is the work.
struct FeaturedStory: View {
    let article: Article
    var status: String? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var imageFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let url = article.displayImageURL, !dynamicTypeSize.isAccessibilitySize {
                if imageFailed {
                    RoundedRectangle(cornerRadius: OneFeedTheme.cardRadius, style: .continuous)
                        .fill(OneFeedTheme.warm1)
                        .frame(maxWidth: .infinity)
                        .frame(height: OneFeedTheme.featuredHeight)
                        .accessibilityHidden(true)
                } else {
                    ArticleThumbnail(url: url, cornerRadius: OneFeedTheme.cardRadius, maxPixel: 1200, fadesIn: true) {
                        imageFailed = true
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: OneFeedTheme.featuredHeight)
                    .clipped()
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                GalleryLabel(text: ArticlePresentation.sourceName(for: article))
                Text(article.title)
                    .font(.system(.title, design: .serif))
                    .foregroundStyle(OneFeedTheme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let excerpt = article.displayExcerpt {
                    Text(excerpt)
                        .font(.subheadline)
                        .foregroundStyle(OneFeedTheme.graphite)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(byline)
                    .font(.caption)
                    .foregroundStyle(OneFeedTheme.graphite)
                    .fixedSize(horizontal: false, vertical: true)
                if let status {
                    Text(status)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(OneFeedTheme.graphite)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Label(openTitle, systemImage: openSymbol)
                        .labelStyle(.titleAndIcon)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.right")
                        .accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OneFeedTheme.ink)
                .padding(.top, 14)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(OneFeedTheme.separator)
                        .frame(height: 0.5)
                        .accessibilityHidden(true)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, OneFeedTheme.pagePadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(article.isCurrentReading ? .isSelected : [])
        .accessibilityHint("Opens this article")
        .onChange(of: article.imageURL) { _, _ in
            imageFailed = false
        }
    }

    private var byline: String {
        var parts = [OneFeedDateLabel.monthDayAndYear(article.publishedAt)]
        if let duration = article.timedDurationPhrase { parts.append(duration) }
        return parts.joined(separator: "  ·  ")
    }

    private var openTitle: String {
        switch article.contentKind {
        case "youtube": return String(localized: "Watch video")
        case "podcast", "music": return String(localized: "Listen")
        case "pdf": return String(localized: "Read PDF")
        case "epub": return String(localized: "Read book")
        default:
            return article.isCurrentReading
                ? String(localized: "Continue reading")
                : String(localized: "Start reading")
        }
    }

    private var openSymbol: String {
        switch article.contentKind {
        case "youtube": "play.rectangle"
        case "podcast", "music": "headphones"
        case "pdf": "doc.text"
        case "epub": "book.closed"
        default: "book"
        }
    }
}

struct ArticleThumbnail: View {
    let url: URL
    var cornerRadius: CGFloat = 10
    var maxPixel: Int = 192
    var fadesIn = false
    var onUnavailable: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: CGImage?
    @State private var revealed = false

    init(
        url: URL,
        cornerRadius: CGFloat = 10,
        maxPixel: Int = 192,
        fadesIn: Bool = false,
        onUnavailable: (() -> Void)? = nil
    ) {
        self.url = url
        self.cornerRadius = cornerRadius
        self.maxPixel = maxPixel
        self.fadesIn = fadesIn
        self.onUnavailable = onUnavailable
    }

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .opacity((fadesIn && !revealed && !reduceMotion) ? 0 : 1)
                }
            }
            .clipped()
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
            .task(id: url) {
                revealed = false
                let loaded = await ThumbnailCache.shared.image(for: url, maxPixel: maxPixel)
                guard !Task.isCancelled else { return }
                if let loaded {
                    image = loaded
                    reveal()
                } else {
                    image = nil
                    onUnavailable?()
                }
            }
    }

    private func reveal() {
        guard fadesIn else {
            revealed = true
            return
        }
        if reduceMotion {
            revealed = true
        } else {
            withAnimation(OneFeedMotion.reveal) { revealed = true }
        }
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
                .foregroundStyle(OneFeedTheme.stone)
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
            .clipShape(.rect(cornerRadius: OneFeedTheme.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: OneFeedTheme.radius, style: .continuous)
                    .strokeBorder(OneFeedTheme.sand, lineWidth: 1)
            }
    }
}

struct FeedDirectoryRow: View {
    let title: String
    var systemImage: String? = nil
    var emoji: String? = nil
    var count: Int = 0
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(OneFeedTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(OneFeedTheme.graphite)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            UnreadCount(count)
        }
        .frame(minHeight: 48)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var leading: some View {
        if let emoji {
            Text(emoji)
                .font(.system(size: 28))
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
        } else if let systemImage {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(OneFeedTheme.graphite)
                .frame(width: 36, height: 36)
                .background(OneFeedTheme.warm1, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

/// Paper and pressed feedback share a shape; iOS lists supply the outer corners.
struct ArticleCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: OneFeedTheme.cardRadius, style: .continuous)
        configuration.label
            .background(configuration.isPressed ? OneFeedTheme.warm1 : OneFeedTheme.paper, in: shape)
            .clipShape(shape)
            #if os(macOS)
            .overlay {
                shape.strokeBorder(OneFeedTheme.sand, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            #endif
            .contentShape(shape)
            .scaleEffect((reduceMotion || !configuration.isPressed) ? 1 : 0.99)
            .animation(reduceMotion ? nil : OneFeedMotion.press, value: configuration.isPressed)
    }
}

struct DirectoryRowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? OneFeedTheme.warm1 : Color.clear)
            .scaleEffect((reduceMotion || !configuration.isPressed) ? 1 : 0.97)
            .animation(reduceMotion ? nil : OneFeedMotion.press, value: configuration.isPressed)
    }
}

struct UnreadCount: View {
    let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ count: Int) {
        self.count = count
    }

    var body: some View {
        if count > 0 {
            countLabel
                .accessibilityLabel("\(count) unread")
        }
    }

    @ViewBuilder
    private var countLabel: some View {
        let label = Text("\(count)")
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(OneFeedTheme.ink)
        if reduceMotion {
            label
        } else {
            label
                .contentTransition(.numericText())
                .animation(OneFeedMotion.overlay, value: count)
        }
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
                    .foregroundStyle(star <= rating ? OneFeedTheme.ink : OneFeedTheme.sand)
            }
        }
        .accessibilityHidden(true)
    }
}

struct ArticleRatingControl: View {
    let article: Article
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @State private var saveError: String?

    var body: some View {
        if article.isStored {
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        let next = article.rating == star ? 0 : star
                        withAnimation(reduceMotion ? nil : OneFeedMotion.press) {
                            saveRating(next)
                        }
                    } label: {
                        Image(systemName: star <= article.rating ? "star.fill" : "star")
                            .font(.body)
                            .foregroundStyle(star <= article.rating ? OneFeedTheme.ink : OneFeedTheme.sand)
                            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                    .accessibilityAddTraits(star <= article.rating ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(article.rating == 0 ? "Rating" : "Rated \(article.rating) of 5")
            .alert("Couldn’t save that rating", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func saveRating(_ stars: Int) {
        do {
            try ArticleActions.rate(article, stars: stars, in: modelContext)
        } catch {
            saveError = UserFacingFailure.message(for: error, fallback: "Couldn’t save that rating.")
        }
    }
}

struct EmptyLibraryState: View {
    let title: String
    let systemImage: String
    let description: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    VStack(spacing: 16) {
                        Image(systemName: systemImage)
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(OneFeedTheme.accent)
                            .accessibilityHidden(true)
                            .padding(.top, 12)
                        Text(title)
                            .font(.system(.title, design: .serif))
                            .foregroundStyle(OneFeedTheme.ink)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        if let actionTitle, let action {
                            Button(actionTitle, action: action)
                                .buttonStyle(PrimaryActionStyle())
                                .padding(.top, 4)
                        }
                        if let secondaryTitle, let secondaryAction {
                            Button(secondaryTitle, action: secondaryAction)
                                .font(.body)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundStyle(OneFeedTheme.graphite)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        Text(description)
                            .font(.body)
                            .foregroundStyle(OneFeedTheme.graphite)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 96)
                    .frame(maxWidth: .infinity)
                    .oneFeedMacEmptyCanvas()
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                emptyContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OneFeedTheme.plaster)
    }

    private var emptyContent: some View {
        ContentUnavailableView {
            VStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(OneFeedTheme.accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(.title, design: .serif))
                    .foregroundStyle(OneFeedTheme.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } description: {
            Text(description)
                .font(.body)
                .foregroundStyle(OneFeedTheme.graphite)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        } actions: {
            VStack(spacing: 12) {
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(PrimaryActionStyle(expands: false))
                }
                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(OneFeedTheme.graphite)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .oneFeedMacEmptyCanvas()
        }
    }
}

extension View {
    @ViewBuilder
    func articleListRow(isCurrent: Bool = false, isSelected: Bool = false) -> some View {
        listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            .listRowSeparator(.visible, edges: .bottom)
            .listRowSeparatorTint(OneFeedTheme.sand, edges: .bottom)
            .listRowBackground(isCurrent ? OneFeedTheme.current : (isSelected ? OneFeedTheme.warm1 : OneFeedTheme.paper))
    }

    func oneFeedDirectoryRow() -> some View {
        listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(OneFeedTheme.paper)
    }

    func articleTimelineList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(OneFeedTheme.plaster)
            // Clear the floating tab bar so the last row is never trapped under it.
            .contentMargins(.bottom, 88, for: .scrollContent)
            .oneFeedScrollEdge()
    }

    func oneFeedPaperScreen() -> some View {
        scrollContentBackground(.hidden)
            .background(OneFeedTheme.plaster)
            #if os(macOS)
            .alternatingRowBackgrounds(.disabled)
            #endif
    }
}

/// Month-and-day labels for list rows. The same calendar day is formatted once.
enum OneFeedDateLabel {
    private static var monthDay: [Date: String] = [:]
    private static var monthDayYear: [Date: String] = [:]
    private static var longDate: [Date: String] = [:]

    static func monthAndDay(_ date: Date) -> String {
        label(for: date, in: &monthDay) { $0.formatted(.dateTime.month(.abbreviated).day()) }
    }

    static func monthDayAndYear(_ date: Date) -> String {
        label(for: date, in: &monthDayYear) { $0.formatted(.dateTime.month(.abbreviated).day().year()) }
    }

    static func longDate(_ date: Date) -> String {
        label(for: date, in: &longDate) { $0.formatted(date: .long, time: .omitted) }
    }

    private static func label(for date: Date, in store: inout [Date: String], make: (Date) -> String) -> String {
        let day = Calendar.current.startOfDay(for: date)
        if let cached = store[day] { return cached }
        let value = make(date)
        if store.count > 512 { store.removeAll(keepingCapacity: true) }
        store[day] = value
        return value
    }
}
