import SwiftUI
import WebKit

/// First `WebView` after launch pays for WebContent / GPU / Networking processes
/// (several seconds). Keep a 1 pt page in the window so opening the reader
/// does not stall the tap that presented it.
enum ReaderWebWarmup {
    static var isEnabled: Bool {
        let process = ProcessInfo.processInfo
        if process.arguments.contains("-uiTesting") { return false }
        if process.environment["XCTestConfigurationFilePath"] != nil { return false }
        if process.environment["XCTestBundlePath"] != nil { return false }
        return true
    }

    static var skipsOpeningCover: Bool { !isEnabled }
    static let blankURL = URL(string: "about:blank")!
    static let openingCoverTimeout: Duration = .seconds(8)

    static func makeReaderPage() -> WebPage {
        var configuration = WebPage.Configuration()
        configuration.loadsSubresources = true
        // Sanitized reader HTML plus OneFeed's own focus script — not third-party pages.
        configuration.defaultNavigationPreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .nonPersistent()
        return WebPage(configuration: configuration)
    }
}

struct ReaderWebProcessWarmup: View {
    var onReady: () -> Void = {}
    @State private var page = ReaderWebWarmup.makeReaderPage()
    @State private var didSignal = false
    @State private var sawLoad = false

    var body: some View {
        WebView(page)
            .frame(width: 4, height: 4)
            .opacity(0.01)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: page.isLoading) { _, loading in
                if loading {
                    sawLoad = true
                } else if sawLoad {
                    signalReady()
                }
            }
            .task {
                page.load(html: "<!doctype html><html></html>", baseURL: ReaderWebWarmup.blankURL)
                try? await Task.sleep(for: ReaderWebWarmup.openingCoverTimeout)
                signalReady()
            }
    }

    private func signalReady() {
        guard !didSignal else { return }
        didSignal = true
        onReady()
    }
}
