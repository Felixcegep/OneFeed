import SwiftUI
import SwiftData

enum OneFeedTheme {
    /// Terracotta verb — send, select, link, caret, mark. Not titles, body, or rules.
    static let accent = Color(red: 0.851, green: 0.467, blue: 0.341)
    static let accentPressed = Color(red: 0.745, green: 0.384, blue: 0.259)
    static let accentSoft = Color(red: 0.949, green: 0.867, blue: 0.816)
    /// Sage for Done. Terracotta stays the Save verb.
    static let sage = Color(red: 0.420, green: 0.616, blue: 0.369)
    /// Error red with the same clay undertone as the accent.
    static let error = Color(red: 0.757, green: 0.400, blue: 0.329)

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

/// Section headers only: 11pt bold, slight tracking, stone. Not a row title.
struct GalleryLabel: View {
    let text: String
    var pigment = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(0.4)
            .textCase(.uppercase)
            .foregroundStyle(pigment ? OneFeedTheme.accent : OneFeedTheme.stone)
            .lineLimit(1)
    }
}

/// Sticky list header with plaster behind the type so rows cannot show through.
struct GallerySectionHeader: View {
    let text: String

    var body: some View {
        GalleryLabel(text: text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .background(OneFeedTheme.plaster)
    }
}

/// Ink fill, cream type, capsule. Press scales to 0.97 — no offset shadow.
struct PrimaryActionStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OneFeedTheme.sansUI(16, weight: .medium))
            .foregroundStyle(OneFeedTheme.plaster)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(OneFeedTheme.ink, in: Capsule())
            .scaleEffect((reduceMotion || !configuration.isPressed) ? 1 : 0.97)
            .animation(reduceMotion ? nil : OneFeedMotion.press, value: configuration.isPressed)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.55), trigger: configuration.isPressed)
    }
}

/// Compact ink capsule for the reader Done verb.
struct InkCapsuleStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OneFeedTheme.sansUI(15, weight: .medium))
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
            .font(OneFeedTheme.sansUI(15, weight: .medium))
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

struct ArticleRow: View {
    let article: Article
    var status: String? = nil
    @State private var imageFailed = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let url = article.displayImageURL, !imageFailed {
                ArticleThumbnail(url: url, cornerRadius: OneFeedTheme.radius) {
                    imageFailed = true
                }
                .frame(width: OneFeedTheme.thumbnailWidth, height: OneFeedTheme.thumbnailHeight)
                .clipped()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(OneFeedTheme.sansUI(15, weight: .medium))
                    .foregroundStyle(OneFeedTheme.ink)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(meta)
                    .font(OneFeedTheme.sansUI(12, weight: .regular))
                    .foregroundStyle(OneFeedTheme.stone)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this article")
        .onChange(of: article.imageURL) { _, _ in
            imageFailed = false
        }
    }

    private var meta: String {
        var parts: [String] = []
        if let source = article.feed?.title, !source.isEmpty { parts.append(source) }
        if let kind = article.kindLabel { parts.append(kind) }
        if let duration = article.timedDurationPhrase { parts.append(duration) }
        parts.append(article.publishedAt.formatted(.dateTime.month(.abbreviated).day()))
        if article.rating > 0 { parts.append(String(repeating: "★", count: article.rating)) }
        if let status { parts.append(status) }
        return parts.joined(separator: "  ·  ")
    }
}

/// Photograph on paper, then authored serif. The crop is the work.
struct FeaturedStory: View {
    let article: Article
    @State private var imageFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let url = article.displayImageURL, !imageFailed {
                ArticleThumbnail(url: url, cornerRadius: OneFeedTheme.cardRadius, fadesIn: true) {
                    imageFailed = true
                }
                .frame(maxWidth: .infinity)
                .frame(height: OneFeedTheme.featuredHeight)
                .clipped()
            }

            VStack(alignment: .leading, spacing: 10) {
                GalleryLabel(text: article.feed?.title ?? "Source")
                Text(article.title)
                    .font(OneFeedTheme.serifDisplay(24))
                    .foregroundStyle(OneFeedTheme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let excerpt = article.displayExcerpt {
                    Text(excerpt)
                        .font(OneFeedTheme.serifBody(16))
                        .foregroundStyle(OneFeedTheme.graphite)
                        .lineLimit(2)
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
        .onChange(of: article.imageURL) { _, _ in
            imageFailed = false
        }
    }

    private var byline: String {
        var parts = [article.publishedAt.formatted(.dateTime.month(.abbreviated).day().year())]
        if let duration = article.timedDurationPhrase { parts.append(duration) }
        return parts.joined(separator: "  ·  ")
    }
}

struct ArticleThumbnail: View {
    let url: URL
    var cornerRadius: CGFloat = 10
    var fadesIn = false
    var onUnavailable: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    init(url: URL, cornerRadius: CGFloat = 10, fadesIn: Bool = false, onUnavailable: (() -> Void)? = nil) {
        self.url = url
        self.cornerRadius = cornerRadius
        self.fadesIn = fadesIn
        self.onUnavailable = onUnavailable
    }

    var body: some View {
        Color.clear
            .overlay {
                AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                            .opacity((fadesIn && !revealed && !reduceMotion) ? 0 : 1)
                            .onAppear { reveal() }
                    case .failure:
                        Color.clear
                            .task { onUnavailable?() }
                    default:
                        Color.clear
                    }
                }
            }
            .clipped()
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .onChange(of: url) { _, _ in
                revealed = false
            }
            .accessibilityHidden(true)
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
    var swatchName: String? = nil
    var count: Int = 0

    var body: some View {
        HStack(spacing: 14) {
            leading
            Text(title)
                .font(OneFeedTheme.sansUI(15, weight: .medium))
                .foregroundStyle(OneFeedTheme.ink)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            UnreadCount(count)
        }
        .frame(minHeight: 44)
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
                .foregroundStyle(OneFeedTheme.graphite)
                .frame(width: 16)
                .accessibilityHidden(true)
        }
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

    init(_ count: Int) {
        self.count = count
    }

    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(.system(size: 13, weight: .regular).monospacedDigit())
                .foregroundStyle(OneFeedTheme.stone)
                .contentTransition(.numericText())
                .animation(OneFeedMotion.overlay, value: count)
                .accessibilityLabel("\(count) unread")
        }
    }
}

struct FolderSwatch: View {
    let name: String

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(tint)
            .frame(width: 3, height: 16)
            .accessibilityHidden(true)
    }

    private var tint: Color {
        let palette: [Color] = [
            Color(red: 0.851, green: 0.467, blue: 0.341),
            Color(red: 0.722, green: 0.478, blue: 0.310),
            Color(red: 0.420, green: 0.490, blue: 0.369),
            Color(red: 0.353, green: 0.310, blue: 0.267),
            Color(red: 0.541, green: 0.494, blue: 0.447),
            Color(red: 0.176, green: 0.145, blue: 0.125)
        ]
        let index = abs(name.hashValue & Int.max) % palette.count
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
                    .foregroundStyle(star <= rating ? OneFeedTheme.ink : OneFeedTheme.sand)
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
                        withAnimation(OneFeedMotion.press) {
                            article.setRating(article.rating == star ? 0 : star)
                            try? article.modelContext?.save()
                        }
                    } label: {
                        Image(systemName: star <= article.rating ? "star.fill" : "star")
                            .font(.body)
                            .foregroundStyle(star <= article.rating ? OneFeedTheme.ink : OneFeedTheme.sand)
                            .contentTransition(.symbolEffect(.replace))
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
            VStack(spacing: 20) {
                OneFeedMark(size: 40)
                Text(title)
                    .font(OneFeedTheme.serifDisplay(32))
                    .foregroundStyle(OneFeedTheme.ink)
                    .multilineTextAlignment(.center)
            }
        } description: {
            Text(description)
                .font(OneFeedTheme.sansUI(16, weight: .regular))
                .foregroundStyle(OneFeedTheme.graphite)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PrimaryActionStyle())
            }
        }
    }
}

extension View {
    @ViewBuilder
    func articleListRow() -> some View {
        #if os(iOS)
        listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
            .listRowSeparatorTint(OneFeedTheme.sand)
            .listRowBackground(OneFeedTheme.plaster)
        #else
        listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
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

    func oneFeedPaperScreen() -> some View {
        scrollContentBackground(.hidden)
            .background(OneFeedTheme.plaster)
    }
}
