import PDFKit
import SwiftUI

struct PDFReaderPane: View {
    let url: URL

    var body: some View {
        PDFKitRepresentedView(url: url)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OneFeedTheme.paper)
            .accessibilityLabel("PDF")
    }
}

#if os(macOS)
private struct PDFKitRepresentedView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        configure(view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }

    private func configure(_ view: PDFView) {
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = NSColor(OneFeedTheme.paper)
        view.pageShadowsEnabled = false
        view.document = PDFDocument(url: url)
    }
}
#else
private struct PDFKitRepresentedView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        configure(view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }

    private func configure(_ view: PDFView) {
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(OneFeedTheme.paper)
        view.pageShadowsEnabled = false
        view.document = PDFDocument(url: url)
    }
}
#endif
