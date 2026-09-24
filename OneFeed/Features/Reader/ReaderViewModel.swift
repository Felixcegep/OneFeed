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
    private(set) var isAskingVideo = false
    var summaryError: String?
    var askError: String?
    var bodyError: String?
    private let gemini: GeminiClient
    private var videoAsk: Task<Void, Never>?
    private var summaryTask: Task<Void, Never>?

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

    var videoChatMessages: [VideoChatMessage] {
        VideoChatLog.decode(article.videoChatJSON)
    }

    func enrichReadableHTML() async {
        if article.contentKind == "epub" {
            await loadEPUBIfNeeded()
            return
        }
        if article.contentKind == "pdf" {
            await loadPDFTextIfNeeded()
            return
        }
        guard article.contentKind == "article" else { return }
        let existing = article.contentHTML ?? article.summary
        guard ArticleExtractionPolicy().shouldFetchPage(rssHTML: existing, kind: article.contentKind) else { return }
        isExtracting = true
        defer { isExtracting = false }
        guard let html = await ArticleExtractionService().extractedHTML(for: article) else { return }
        do {
            try Task.checkCancellation()
        } catch {
            return
        }
        if html != article.contentHTML {
            article.contentHTML = html
        }
        article.refreshEstimatedReadingMinutes()
        if let failure = saveArticleChanges() {
            bodyError = failure
        }
    }

    func declineYouTubeSummary() {
        article.declinedVideoSummary = true
        try? article.modelContext?.save()
    }

    func beginSummary() {
        summaryTask?.cancel()
        summaryTask = Task { await self.summarizeYouTube() }
    }

    func cancelSummary() {
        summaryTask?.cancel()
        summaryTask = nil
    }

    func summarizeYouTube() async {
        guard let url = youtubeURL else {
            summaryError = ReaderFailure.message(for: GeminiClientError.missingVideo)
            return
        }
        isSummarizing = true
        summaryError = nil
        defer { isSummarizing = false }
        do {
            let reply = try await gemini.summarizeYouTube(url: url)
            try Task.checkCancellation()
            article.aiSummary = reply.text
            article.videoGeminiInteractionID = reply.id
            var messages = VideoChatLog.decode(article.videoChatJSON)
            if messages.isEmpty {
                messages.append(
                    VideoChatMessage(
                        id: UUID(),
                        role: .model,
                        text: reply.text,
                        createdAt: Date()
                    )
                )
            }
            if let failure = persistVideoChat(messages) {
                summaryError = failure
            }
        } catch is CancellationError {
            return
        } catch {
            summaryError = ReaderFailure.message(for: error)
        }
    }

    func beginVideoQuestion(_ question: String) {
        videoAsk?.cancel()
        videoAsk = Task { await self.askAboutVideo(question) }
    }

    func cancelVideoWork() {
        videoAsk?.cancel()
        videoAsk = nil
    }

    func askAboutVideo(_ question: String) async {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        guard let url = youtubeURL else {
            askError = ReaderFailure.message(for: GeminiClientError.missingVideo)
            return
        }

        let recentTurns = videoChatMessages
        var messages = recentTurns
        messages.append(
            VideoChatMessage(
                id: UUID(),
                role: .user,
                text: question,
                createdAt: Date()
            )
        )
        if let failure = persistVideoChat(messages) {
            askError = failure
        }

        isAskingVideo = true
        askError = nil
        defer { isAskingVideo = false }
        do {
            let reply = try await gemini.askYouTube(
                url: url,
                question: question,
                previousInteractionID: article.videoGeminiInteractionID,
                summary: article.aiSummary,
                recentTurns: recentTurns
            )
            try Task.checkCancellation()
            article.videoGeminiInteractionID = reply.id
            var updated = videoChatMessages
            updated.append(
                VideoChatMessage(
                    id: UUID(),
                    role: .model,
                    text: reply.text,
                    createdAt: Date()
                )
            )
            if let failure = persistVideoChat(updated) {
                askError = failure
            }
        } catch is CancellationError {
            return
        } catch {
            askError = ReaderFailure.message(for: error)
        }
    }

    /// Stores the transcript. Returns a sentence when the save does not land. The messages stay on screen either way.
    private func persistVideoChat(_ messages: [VideoChatMessage]) -> String? {
        article.videoChatJSON = VideoChatLog.encode(VideoChatLog.trimmed(messages))
        guard let context = article.modelContext else {
            return "Couldn’t save that conversation."
        }
        LibraryChange.note(article)
        do {
            try context.save()
            return nil
        } catch {
            return UserFacingFailure.message(for: error, fallback: "Couldn’t save that conversation.")
        }
    }

    private var cachedDocument: (key: String, html: String)?
    private var cachedBodyHash: (text: String, hash: Int)?
    private var cachedSummaryHash: (text: String, hash: Int)?
    private var cachedVideoBody: (summary: String, html: String)?

    /// Date and length under the title. Kept off the document cache key so a late duration does not reload the page.
    var readerMetaLine: String {
        [
            OneFeedDateLabel.longDate(article.publishedAt),
            article.durationPhrase,
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    var documentBaseURL: URL {
        if article.contentKind == "epub",
           let hash = ImportedDocumentStore.hash(fromGuid: article.guid) {
            let extracted = ImportedDocumentStore.shared.extractedDirectory(hash: hash)
            return EPUBReader.opfDirectory(in: extracted) ?? ReaderWebWarmup.blankURL
        }
        return ReaderWebWarmup.blankURL
    }

    func documentHTML(fontChoice: ReaderFontChoice, textSize: ReaderTextSize, boldText: Bool = false) -> String {
        let fallback = switch article.contentKind {
        case "epub":
            "<p>This book couldn’t be opened. Import the EPUB again.</p>"
        case "pdf":
            "<p>This PDF doesn’t have selectable text. Open the PDF view to read the pages.</p>"
        case "youtube":
            "<p>Summarize this video to read it here. The video stays available from the switcher above.</p>"
        default:
            "<p>This source only provided metadata. Open the original article to continue reading.</p>"
        }
        let summary = article.aiSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawBody: String
        if article.contentKind == "youtube", !summary.isEmpty {
            if let cachedVideoBody, cachedVideoBody.summary == summary {
                rawBody = cachedVideoBody.html
            } else {
                rawBody = ReaderHTML.videoSummaryBody(from: summary)
                cachedVideoBody = (summary, rawBody)
            }
        } else {
            rawBody = article.readableHTML ?? fallback
        }
        #if canImport(UIKit)
        let typeSize = UIApplication.shared.preferredContentSizeCategory.rawValue
        #else
        let typeSize = "standard"
        #endif
        // Length and date stay out of this key. A late duration must not rebuild the page.
        // The body hash is remembered, so a redraw does not walk the article again.
        let key = "\(article.id.uuidString)|\(fingerprint(rawBody, cache: &cachedBodyHash))|\(fingerprint(summary, cache: &cachedSummaryHash))|\(fontChoice.rawValue)|\(textSize.rawValue)|\(typeSize)|\(boldText ? "bold" : "regular")|\(article.title)|\(article.feed?.title ?? "")|focus\(ReaderFocus.engineVersion)"
        if let cachedDocument, cachedDocument.key == key {
            return cachedDocument.html
        }
        let body = ReaderHTML.sanitizedBody(rawBody)
        let family: String = switch fontChoice {
        case .sans: "-apple-system, BlinkMacSystemFont, sans-serif"
        case .serif: "ui-serif, 'New York', Charter, Georgia, serif"
        case .mono: "ui-monospace, 'SFMono-Regular', Menlo, monospace"
        }
        let bodySize = textSize.points
        let headingSize = max(bodySize * 1.28, bodySize + 5)
        let sectionSize = max(bodySize * 1.12, bodySize + 2)
        #if canImport(UIKit)
        let titleSize = UIFontMetrics(forTextStyle: .title1).scaledValue(for: 28)
        let metaSize = UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 13)
        let sourceSize = UIFontMetrics(forTextStyle: .caption1).scaledValue(for: 11)
        let horizontalPad = 20
        #else
        let titleSize: CGFloat = 32
        let metaSize: CGFloat = 13
        let sourceSize: CGFloat = 11
        let horizontalPad = 48
        #endif
        let metaBits = readerMetaLine
        let bodyWeight = boldText ? 650 : 400
        let headingWeight = boldText ? 700 : 500
        let metaWeight = boldText ? 600 : 400
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root {
          color-scheme: light dark;
        \(OneFeedPalette.readerRootCSS)
        }
        \(OneFeedPalette.readerContrastCSS)
        html { overflow-x: hidden; }
        body {
          font-family: \(family);
          font-size: \(bodySize)px;
          font-optical-sizing: auto;
          font-weight: \(bodyWeight);
          line-height: 1.55;
          margin: 0 auto;
          padding: 36px \(horizontalPad)px 48px;
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
          font: 700 \(sourceSize)px/1.2 -apple-system, BlinkMacSystemFont, sans-serif;
          letter-spacing: 0.04em;
          text-transform: uppercase;
          color: var(--meta);
        }
        h1 {
          font-family: \(family);
          font-size: \(titleSize)px;
          font-weight: \(headingWeight);
          line-height: 1.22;
          letter-spacing: -0.012em;
          color: var(--title);
          margin: 14px 0 10px;
        }
        .meta {
          font: \(metaWeight) \(metaSize)px/1.45 -apple-system, BlinkMacSystemFont, sans-serif;
          color: var(--meta);
          margin: 0 0 32px;
          padding-bottom: 20px;
          border-bottom: 1px solid var(--rule);
        }
        h2, h3 {
          font-family: \(family);
          font-weight: \(headingWeight);
          line-height: 1.3;
          letter-spacing: -0.01em;
          color: var(--title);
          margin: 1.6em 0 0.45em;
        }
        h2 { font-size: \(headingSize)px; }
        h3 { font-size: \(sectionSize)px; }
        p { margin: 0 0 1.05em; }
        img, video, iframe, figure {
          max-width: 100%;
          height: auto;
          display: block;
          margin: 1.6em 0;
          border-radius: 10px;
        }
        figcaption, cite {
          font: \(metaWeight) \(metaSize)px/1.4 -apple-system, BlinkMacSystemFont, sans-serif;
          color: var(--meta);
          display: block;
          margin-top: 8px;
        }
        a { color: var(--link); text-decoration-thickness: 1px; text-underline-offset: 3px; }
        pre, code { overflow-x: auto; max-width: 100%; }
        pre {
          padding: 16px 18px;
          border-radius: 10px;
          background: color-mix(in srgb, var(--ink) 5%, transparent);
        }
        blockquote {
          margin: 1.6em 0;
          padding: 2px 0 2px 16px;
          border-left: 2px solid var(--quote);
          font-style: italic;
          color: color-mix(in srgb, var(--ink) 86%, var(--meta));
        }
        table { display: block; max-width: 100%; overflow-x: auto; }
        hr { border: 0; border-top: 1px solid var(--rule); margin: 2.2em 0; }
        \(ReaderFocus.pageCSS)
        </style></head><body><div class="source">\(escape(ArticlePresentation.sourceName(for: article)))</div><h1>\(escape(article.title))</h1><div class="meta">\(escape(metaBits))</div><div id="onefeed-article">\(body)</div>\(ReaderFocus.pageScriptTag)</body></html>
        """
        cachedDocument = (key, html)
        return html
    }

    /// Reuses the hash when the text is the same buffer. A redraw should not walk the article.
    private func fingerprint(_ text: String, cache: inout (text: String, hash: Int)?) -> Int {
        if let cache, cache.text == text { return cache.hash }
        let hash = text.hashValue
        cache = (text, hash)
        return hash
    }

    private func loadPDFTextIfNeeded() async {
        if let html = article.contentHTML, !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        guard let file = ImportedDocumentStore.shared.resolvedFileURL(for: article) else { return }
        isExtracting = true
        defer { isExtracting = false }
        let html = await Task.detached {
            (try? ImportedDocumentService.pdfHTML(from: file)) ?? ""
        }.value
        let persisted = ImportedDocumentService.persistedHTML(html)
        guard let persisted else { return }
        article.contentHTML = persisted
        let minutes = ContentClassifier.readingMinutes(words: ContentClassifier.wordCount(in: persisted))
        if minutes > article.estimatedReadingMinutes {
            article.estimatedReadingMinutes = minutes
        }
        if let failure = saveArticleChanges() {
            bodyError = failure
        }
    }

    private func loadEPUBIfNeeded() async {
        if let html = article.contentHTML, !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        guard let file = ImportedDocumentStore.shared.resolvedFileURL(for: article),
              let hash = ImportedDocumentStore.hash(fromGuid: article.guid) else { return }
        isExtracting = true
        defer { isExtracting = false }
        let extracted = ImportedDocumentStore.shared.extractedDirectory(hash: hash)
        do {
            let html = try await Task.detached {
                try EPUBReader.html(fromEPUB: file, extractedTo: extracted)
            }.value
            article.contentHTML = html
            if let failure = saveArticleChanges() {
                bodyError = failure
            }
        } catch {
            return
        }
    }

    /// Keeps the article the reader is showing. Returns a sentence when that write does not land.
    private func saveArticleChanges() -> String? {
        guard let context = article.modelContext else {
            return "Couldn’t keep this article."
        }
        LibraryChange.note(article)
        do {
            try context.save()
            return nil
        } catch {
            return UserFacingFailure.message(for: error, fallback: "Couldn’t keep this article.")
        }
    }

    private func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
