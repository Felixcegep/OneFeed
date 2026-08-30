import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class ReaderViewModel {
    let article: Article

    init(article: Article) { self.article = article }

    func documentHTML(fontChoice: ReaderFontChoice, textSize: ReaderTextSize) -> String {
        let body = article.readableHTML ?? "<p>This source only provided metadata. Open the original article to continue reading.</p>"
        let family: String = switch fontChoice {
        case .sans: "-apple-system, BlinkMacSystemFont, sans-serif"
        case .serif: "ui-serif, 'New York', Georgia, serif"
        case .mono: "ui-monospace, 'SFMono-Regular', Menlo, monospace"
        }
        let bodySize = textSize.points
        #if canImport(UIKit)
        let titleSize = UIFontMetrics(forTextStyle: .title1).scaledValue(for: 34)
        let metaSize = UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 15)
        let sourceSize = UIFontMetrics(forTextStyle: .caption1).scaledValue(for: 13)
        #else
        let titleSize: CGFloat = 34
        let metaSize: CGFloat = 15
        let sourceSize: CGFloat = 13
        #endif
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { color-scheme: light dark; } body { font-family: \(family); font-size: \(bodySize)px; line-height: 1.58; margin: 0 auto; padding: 28px 24px 48px; max-width: 680px; color: CanvasText; background: Canvas; }
        .source { font: 600 \(sourceSize)px/1.2 -apple-system; letter-spacing: 1.1px; text-transform: uppercase; opacity: .56; }
        h1 { font: 650 \(titleSize)px/1.12 -apple-system; letter-spacing: -.8px; margin: 16px 0 12px; } .meta { font: \(metaSize)px/1.35 -apple-system; opacity: .6; margin-bottom: 32px; }
        img, video, iframe { max-width: 100%; height: auto; } a { color: inherit; text-decoration-thickness: 1px; } pre { overflow-x: auto; } blockquote { margin-left: 0; padding-left: 18px; border-left: 2px solid color-mix(in srgb, CanvasText 25%, transparent); }
        </style></head><body><div class="source">\(escape(article.feed?.title ?? "Source"))</div><h1>\(escape(article.title))</h1><div class="meta">\(article.publishedAt.formatted(date: .long, time: .omitted)) · \(article.estimatedReadingMinutes) min read</div>\(body)</body></html>
        """
    }

    private func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
