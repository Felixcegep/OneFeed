import Foundation
import Observation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class ReaderViewModel {
    let article: Article
    private(set) var isExtracting = false
    private(set) var isSummarizing = false
    var summaryError: String?
    private let gemini: GeminiClient

    init(article: Article, gemini: GeminiClient = GeminiClient()) {
        self.article = article
        self.gemini = gemini
    }

    var hasAISummary: Bool {
        guard let aiSummary = article.aiSummary else { return false }
        return !aiSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var shouldOfferYouTubeSummary: Bool {
        article.contentKind == "youtube"
            && !hasAISummary
            && !article.declinedVideoSummary
            && youtubeURL != nil
    }

    var youtubeURL: URL? {
        article.videoID.flatMap { YouTubeProcessor.watchURL(for: $0) } ?? article.url
    }

    func enrichReadableHTML() async {
        guard article.contentKind == "article" else { return }
        isExtracting = true
        defer { isExtracting = false }
        if let html = await ArticleExtractionService().extractedHTML(for: article), html != article.contentHTML {
            article.contentHTML = html
            try? article.modelContext?.save()
        }
    }

    func declineYouTubeSummary() {
        article.declinedVideoSummary = true
        try? article.modelContext?.save()
    }

    func summarizeYouTube() async {
        guard let url = youtubeURL else {
            summaryError = GeminiClientError.missingVideo.localizedDescription
            return
        }
        isSummarizing = true
        summaryError = nil
        defer { isSummarizing = false }
        do {
            let text = try await gemini.summarizeYouTube(url: url)
            article.aiSummary = text
            try? article.modelContext?.save()
        } catch {
            summaryError = error.localizedDescription
        }
    }

    func documentHTML(fontChoice: ReaderFontChoice, textSize: ReaderTextSize) -> String {
        let fallback = "<p>This source only provided metadata. Open the original article to continue reading.</p>"
        let body = ReaderHTML.sanitizedBody(article.readableHTML ?? fallback)
        let family: String = switch fontChoice {
        case .sans: "-apple-system, BlinkMacSystemFont, sans-serif"
        case .serif: "ui-serif, 'New York', Charter, Georgia, serif"
        case .mono: "ui-monospace, 'SFMono-Regular', Menlo, monospace"
        }
        let bodySize = textSize.points
        let headingSize = max(bodySize * 1.42, bodySize + 7)
        let sectionSize = max(bodySize * 1.18, bodySize + 3)
        #if canImport(UIKit)
        let titleSize = UIFontMetrics(forTextStyle: .title1).scaledValue(for: 32)
        let metaSize = UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 14)
        let sourceSize = UIFontMetrics(forTextStyle: .caption1).scaledValue(for: 12)
        let horizontalPad = 28
        #else
        let titleSize: CGFloat = 34
        let metaSize: CGFloat = 14
        let sourceSize: CGFloat = 12
        let horizontalPad = 48
        #endif
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root {
          color-scheme: light dark;
          --paper: transparent;
          --ink: light-dark(#1A1916, #F3F0EA);
          --title: light-dark(#141311, #F7F4EE);
          --meta: light-dark(#6F6A62, #A39E95);
          --rule: light-dark(#E4DFD6, #2A2824);
          --link: light-dark(#C14A1C, #E07A4A);
          --quote: light-dark(#C14A1C, #E07A4A);
        }
        html { overflow-x: hidden; }
        body {
          font-family: \(family);
          font-size: \(bodySize)px;
          font-optical-sizing: auto;
          font-weight: 400;
          line-height: 1.78;
          margin: 0 auto;
          padding: 40px \(horizontalPad)px 180px;
          max-width: 36em;
          color: var(--ink);
          background: var(--paper);
          overflow-x: hidden;
          overflow-wrap: anywhere;
          word-break: break-word;
          hyphens: auto;
          -webkit-hyphens: auto;
        }
        .source {
          font: 500 \(sourceSize)px/1.2 -apple-system, BlinkMacSystemFont, sans-serif;
          letter-spacing: 0.18em;
          text-transform: uppercase;
          color: var(--quote);
        }
        h1 {
          font-family: \(family);
          font-size: \(titleSize)px;
          font-weight: 500;
          line-height: 1.18;
          letter-spacing: -0.018em;
          color: var(--title);
          margin: 18px 0 12px;
        }
        .meta {
          font: 400 \(metaSize)px/1.45 -apple-system, BlinkMacSystemFont, sans-serif;
          letter-spacing: 0.04em;
          color: var(--meta);
          margin: 0 0 36px;
          padding-bottom: 24px;
          border-bottom: 1px solid var(--rule);
        }
        h2, h3 {
          font-family: \(family);
          font-weight: 500;
          line-height: 1.28;
          letter-spacing: -0.012em;
          color: var(--title);
          margin: 1.8em 0 0.5em;
        }
        h2 { font-size: \(headingSize)px; }
        h3 { font-size: \(sectionSize)px; }
        p { margin: 0 0 1.15em; }
        img, video, iframe, figure {
          max-width: 100%;
          height: auto;
          display: block;
          margin: 1.8em 0;
          border-radius: 2px;
        }
        figcaption, cite {
          font: 400 \(metaSize)px/1.4 -apple-system, BlinkMacSystemFont, sans-serif;
          letter-spacing: 0.04em;
          color: var(--meta);
          display: block;
          margin-top: 8px;
        }
        a { color: var(--link); text-decoration-thickness: 1px; text-underline-offset: 3px; }
        pre, code { overflow-x: auto; max-width: 100%; }
        pre {
          padding: 16px 18px;
          border-radius: 2px;
          background: color-mix(in srgb, var(--ink) 5%, transparent);
        }
        blockquote {
          margin: 1.8em 0;
          padding: 2px 0 2px 18px;
          border-left: 1px solid var(--quote);
          font-style: italic;
          color: color-mix(in srgb, var(--ink) 86%, var(--meta));
        }
        table { display: block; max-width: 100%; overflow-x: auto; }
        hr { border: 0; border-top: 1px solid var(--rule); margin: 2.4em 0; }
        </style></head><body><div class="source">\(escape(article.feed?.title ?? "Source"))</div><h1>\(escape(article.title))</h1><div class="meta">\(article.publishedAt.formatted(date: .long, time: .omitted)) · \(article.durationPhrase)</div>\(body)</body></html>
        """
    }

    private func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
