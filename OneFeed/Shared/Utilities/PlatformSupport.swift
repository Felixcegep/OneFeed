#if os(macOS)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
import SwiftUI

extension Color {
    /// Warm gallery plaster / black-box wall. COS and museum sites treat the wall as a material.
    static var oneFeedPlaster: Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: "OneFeedPlaster", dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.09, green: 0.085, blue: 0.078, alpha: 1)
                : NSColor(srgbRed: 0.965, green: 0.953, blue: 0.933, alpha: 1)
        }))
        #else
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.09, green: 0.085, blue: 0.078, alpha: 1)
                : UIColor(red: 0.965, green: 0.953, blue: 0.933, alpha: 1)
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
            .background(OneFeedTheme.plaster)
        #else
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(OneFeedTheme.plaster)
        #endif
    }

    func oneFeedScrollEdge() -> some View {
        scrollEdgeEffectStyle(.soft, for: .top)
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

    /// macOS sheets size to their content. A fitted card keeps the reader from
    /// filling the display; `WebView` still needs an explicit frame.
    @ViewBuilder
    func oneFeedMacSheetCanvas() -> some View {
        #if os(macOS)
        self
            .frame(width: OneFeedTheme.readerWidth, height: OneFeedTheme.readerHeight)
            .clipShape(.rect(cornerRadius: OneFeedTheme.readerCorner, style: .continuous))
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
        sheet(isPresented: isPresented, content: content)
        #endif
    }
}

enum OneFeedNotify {
    static let subscribe = Notification.Name("onefeed.subscribe")
    static let refresh = Notification.Name("onefeed.refresh")
}
