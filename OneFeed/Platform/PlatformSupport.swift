#if os(macOS)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
import SwiftUI

/// Whether a keyboard frame covers the floating tab bar. A docked keyboard meets the bottom of the screen. A floating one does not.
enum OneFeedKeyboardClearance {
    static func coversBottom(keyboardMinY: CGFloat, keyboardMaxY: CGFloat, screenMaxY: CGFloat) -> Bool {
        guard screenMaxY > 1, keyboardMaxY > keyboardMinY else { return false }
        let overlap = screenMaxY - keyboardMinY
        return keyboardMaxY >= screenMaxY - 1 && overlap > 44
    }
}

#if os(iOS)
private struct OneFeedTabBarClearance: ViewModifier {
    @State private var keyboardCoversBottom = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: keyboardCoversBottom ? 0 : 96)
            }
            .animation(nil, value: keyboardCoversBottom)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                keyboardCoversBottom = Self.coversBottom(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardCoversBottom = false
            }
    }

    private static func coversBottom(_ note: Notification) -> Bool {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return false }
        guard let screenMaxY = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .bounds.maxY
        else { return false }
        return OneFeedKeyboardClearance.coversBottom(
            keyboardMinY: frame.minY,
            keyboardMaxY: frame.maxY,
            screenMaxY: screenMaxY
        )
    }
}
#endif

extension Color {
    static var oneFeedSystemBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    static var oneFeedGroupedBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }

    static var oneFeedSecondaryGroupedBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }

    static var oneFeedTertiaryFill: Color {
        #if os(macOS)
        Color(nsColor: .separatorColor).opacity(0.35)
        #else
        Color(uiColor: .tertiarySystemFill)
        #endif
    }

    static var oneFeedSeparator: Color {
        #if os(macOS)
        Color(nsColor: .separatorColor)
        #else
        Color(uiColor: .separator)
        #endif
    }
}

extension ToolbarItemPlacement {
    static var oneFeedLeading: ToolbarItemPlacement {
        #if os(macOS)
        .cancellationAction
        #else
        .topBarLeading
        #endif
    }

    static var oneFeedTrailing: ToolbarItemPlacement {
        #if os(macOS)
        .primaryAction
        #else
        .topBarTrailing
        #endif
    }

    /// Stays visible when the navigation bar collapses or items move into overflow.
    static var oneFeedPinnedTrailing: ToolbarItemPlacement {
        #if os(iOS)
        .topBarPinnedTrailing
        #else
        .primaryAction
        #endif
    }

    static var oneFeedBottomBar: ToolbarItemPlacement {
        #if os(macOS)
        .automatic
        #else
        .bottomBar
        #endif
    }
}

extension View {
    @ViewBuilder
    func oneFeedInlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func oneFeedLargeTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.large)
        #else
        self
        #endif
    }

    @ViewBuilder
    func oneFeedAutocapitalizationNever() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    @ViewBuilder
    func oneFeedAutocapitalizationWords() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.words)
        #else
        self
        #endif
    }

    @ViewBuilder
    func oneFeedSubmitGo() -> some View {
        #if os(iOS)
        submitLabel(.go)
        #else
        self
        #endif
    }

    @ViewBuilder
    func oneFeedURLKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.URL)
        #else
        self
        #endif
    }

    @ViewBuilder
    func oneFeedGroupedListStyle() -> some View {
        #if os(macOS)
        listStyle(.inset)
            .scrollContentBackground(.hidden)
            .alternatingRowBackgrounds(.disabled)
            .background(OneFeedTheme.plaster)
            .oneFeedMacReadingColumn()
        #else
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(OneFeedTheme.plaster)
            .listSectionSpacing(22)
            .scrollIndicators(.hidden, axes: .vertical)
            .contentMargins(.bottom, 132, for: .scrollContent)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
        #endif
    }

    /// Phone tab-bar clearance only. Mac windows have no floating tabs.
    /// A docked keyboard already covers the tab bar, so the spacer leaves while it is up.
    @ViewBuilder
    func oneFeedTabBarClearance() -> some View {
        #if os(iOS)
        modifier(OneFeedTabBarClearance())
        #else
        self
        #endif
    }

    /// Settings and destination lists stay a reading-width column on Mac.
    @ViewBuilder
    func oneFeedMacReadingColumn() -> some View {
        #if os(macOS)
        frame(maxWidth: OneFeedTheme.readingColumnWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        self
        #endif
    }

    @ViewBuilder
    func oneFeedMacFormColumn() -> some View {
        #if os(macOS)
        frame(maxWidth: OneFeedTheme.formColumnWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        self
        #endif
    }

    @ViewBuilder
    func oneFeedMacEmptyCanvas() -> some View {
        #if os(macOS)
        frame(maxWidth: 400)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        self
        #endif
    }

    @ViewBuilder
    func oneFeedSettingsCanvas() -> some View {
        scrollContentBackground(.hidden)
            .background(OneFeedTheme.plaster)
            #if os(macOS)
            .alternatingRowBackgrounds(.disabled)
            #endif
            .oneFeedTabBarClearance()
            .oneFeedMacFormColumn()
    }

    @ViewBuilder
    func oneFeedWindowPlaster() -> some View {
        #if os(macOS)
        containerBackground(OneFeedTheme.plaster, for: .window)
            .toolbarBackground(OneFeedTheme.plaster, for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
        #else
        self
        #endif
    }

    func oneFeedFloatingTabClearance() -> some View {
        #if os(iOS)
        safeAreaPadding(.bottom, 88)
        #else
        self
        #endif
    }

    /// Sidebar when the window is wide enough, including a resizable iPhone. Compact width stays a tab bar.
    @ViewBuilder
    func oneFeedPreferredSidebar() -> some View {
        #if os(iOS)
        defaultTabBarPlacement(.sidebar)
        #else
        self
        #endif
    }

    func oneFeedScrollEdge() -> some View {
        // Hard edge keeps cream lists readable under Liquid Glass without an opaque
        // toolbarBackground — which paints over large titles on iOS 26+.
        scrollEdgeEffectStyle(.hard, for: .top)
    }

    /// Kept for call-site consistency. On iOS 26+, Liquid Glass owns the bar —
    /// opaque `toolbarBackground` paints over large titles while still reserving space.
    func oneFeedPaperToolbar() -> some View {
        self
    }

    @ViewBuilder
    func oneFeedArticleCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(iOS)
        fullScreenCover(item: item, content: content)
        #else
        sheet(item: item) { value in
            content(value)
                .oneFeedMacSheetCanvas()
        }
        #endif
    }

    /// Reader / browser sheet. Sized to shrink on a short window.
    @ViewBuilder
    func oneFeedMacSheetCanvas() -> some View {
        oneFeedMacSheet(idealWidth: OneFeedTheme.readerWidth, idealHeight: 640)
    }

    /// Forms, pickers, onboarding. Not the 760 × 720 reader frame.
    @ViewBuilder
    func oneFeedMacFormSheet() -> some View {
        oneFeedMacSheet(idealWidth: 480, idealHeight: 520)
    }

    @ViewBuilder
    func oneFeedMacSheet(idealWidth: CGFloat, idealHeight: CGFloat) -> some View {
        #if os(macOS)
        background(OneFeedTheme.plaster)
            .frame(
                minWidth: min(420, idealWidth),
                idealWidth: idealWidth,
                maxWidth: idealWidth + 80,
                minHeight: 380,
                idealHeight: idealHeight,
                maxHeight: idealHeight + 160
            )
            .presentationSizing(.fitted)
            .presentationCornerRadius(OneFeedTheme.readerCorner)
        #else
        self
        #endif
    }

    func oneFeedSearchable(_ text: Binding<String>, prompt: String) -> some View {
        #if os(iOS)
        searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
        #else
        searchable(text: text, prompt: prompt)
        #endif
    }

    @ViewBuilder
    func oneFeedOnboardingCover(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> some View) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented, content: content)
        #else
        sheet(isPresented: isPresented) {
            content()
                .oneFeedMacFormSheet()
        }
        #endif
    }
}

nonisolated enum OneFeedNotify {
    static let subscribe = Notification.Name("onefeed.subscribe")
    static let refresh = Notification.Name("onefeed.refresh")
    static let openFeed = Notification.Name("onefeed.openFeed")
    static let openToday = Notification.Name("onefeed.openToday")
    static let addToQueue = Notification.Name("onefeed.addToQueue")
    static let openQueueArticle = Notification.Name("onefeed.openQueueArticle")
    static let storyIndexDidChange = Notification.Name("onefeed.storyIndexDidChange")
}

enum QueueHandoff {
    @MainActor static var pendingArticleID: UUID?
}
