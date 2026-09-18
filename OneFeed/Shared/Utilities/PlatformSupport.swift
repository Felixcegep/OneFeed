#if os(macOS)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
import SwiftUI

extension Color {
    /// Cream paper canvas. Light `#F8F4ED`, dark `#1F1B16`.
    static var oneFeedPlaster: Color {
        oneFeedAdaptive(
            light: (0.973, 0.957, 0.929),
            dark: (0.122, 0.106, 0.086),
            name: "OneFeedPlaster"
        )
    }

    /// Elevated paper. Light `#FBF9F4`, dark `#2A2520`.
    static var oneFeedPaper: Color {
        oneFeedAdaptive(
            light: (0.984, 0.976, 0.957),
            dark: (0.165, 0.145, 0.125),
            name: "OneFeedPaper"
        )
    }

    /// Pressed / warm fill. Light `#F0EAE0`, dark `#2F2A24`.
    static var oneFeedWarm1: Color {
        oneFeedAdaptive(
            light: (0.941, 0.918, 0.878),
            dark: (0.184, 0.165, 0.141),
            name: "OneFeedWarm1"
        )
    }

    /// Warm ink. Light `#2D2520`, dark `#E8E0D2`. Never cool grey or `#000`.
    static var oneFeedInk: Color {
        oneFeedAdaptive(
            light: (0.176, 0.145, 0.125),
            dark: (0.910, 0.878, 0.824),
            name: "OneFeedInk"
        )
    }

    /// Secondary copy. Light `#5A4F44`, dark `#B8AFA3`.
    static var oneFeedGraphite: Color {
        oneFeedAdaptive(
            light: (0.353, 0.310, 0.267),
            dark: (0.722, 0.686, 0.639),
            name: "OneFeedGraphite"
        )
    }

    /// Error copy, with readable contrast on both paper surfaces.
    static var oneFeedErrorText: Color {
        oneFeedAdaptive(
            light: (0.643, 0.247, 0.196),
            dark: (0.953, 0.631, 0.545),
            name: "OneFeedErrorText"
        )
    }

    /// Tertiary / meta. Light `#8A7E72`, dark `#9C9084`.
    static var oneFeedStone: Color {
        oneFeedAdaptive(
            light: (0.541, 0.494, 0.447),
            dark: (0.612, 0.565, 0.518),
            name: "OneFeedStone"
        )
    }

    /// Hairlines. Light `#DDD2BD`, dark `#3A342C`.
    static var oneFeedSand: Color {
        oneFeedAdaptive(
            light: (0.867, 0.824, 0.741),
            dark: (0.227, 0.204, 0.173),
            name: "OneFeedSand"
        )
    }

    private static func oneFeedAdaptive(
        light: (CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat),
        name: String
    ) -> Color {
        #if os(macOS)
        return Color(nsColor: NSColor(name: name, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: dark.0, green: dark.1, blue: dark.2, alpha: 1)
                : NSColor(srgbRed: light.0, green: light.1, blue: light.2, alpha: 1)
        }))
        #else
        _ = name
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: dark.0, green: dark.1, blue: dark.2, alpha: 1)
                : UIColor(red: light.0, green: light.1, blue: light.2, alpha: 1)
        })
        #endif
    }

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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 96)
            }
        #endif
    }

    /// Phone tab-bar clearance only. Mac windows have no floating tabs.
    @ViewBuilder
    func oneFeedTabBarClearance() -> some View {
        #if os(iOS)
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 96)
        }
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

enum OneFeedNotify {
    static let subscribe = Notification.Name("onefeed.subscribe")
    static let refresh = Notification.Name("onefeed.refresh")
    static let openFeed = Notification.Name("onefeed.openFeed")
    static let openToday = Notification.Name("onefeed.openToday")
}
