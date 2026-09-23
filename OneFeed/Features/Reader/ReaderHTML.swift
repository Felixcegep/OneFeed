import Foundation

enum ReaderHTML {
    private static let dangerousBlock = try! NSRegularExpression(
        pattern: "<(script|style|iframe|object|embed|form|link|meta)(\\s[^>]*)?>[\\s\\S]*?</\\1\\s*>",
        options: [.caseInsensitive]
    )
    private static let dangerousEmpty = try! NSRegularExpression(
        pattern: "<(script|style|iframe|object|embed|form|link|meta)(\\s[^>]*)?/?>",
        options: [.caseInsensitive]
    )
    private static let eventHandler = try! NSRegularExpression(
        pattern: "\\s+on[a-z]+\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)",
        options: [.caseInsensitive]
    )
    private static let javascriptURL = try! NSRegularExpression(
        pattern: "\\s(?:href|src)\\s*=\\s*(?:\"\\s*javascript:[^\"]*\"|'\\s*javascript:[^']*'|javascript:\\S+)",
        options: [.caseInsensitive]
    )

    static func sanitizedBody(_ html: String) -> String {
        var result = html
        result = replace(dangerousBlock, in: result, with: "")
        result = replace(dangerousEmpty, in: result, with: "")
        result = replace(eventHandler, in: result, with: "")
        result = replace(javascriptURL, in: result, with: "")
        if result.range(of: "<img ", options: .caseInsensitive) != nil {
            result = result.replacingOccurrences(
                of: "<img ",
                with: "<img loading=\"lazy\" decoding=\"async\" ",
                options: .caseInsensitive
            )
        }
        return result
    }

    /// Turns a video summary into the same heading-and-paragraph body the article reader already styles.
    static func videoSummaryBody(from summary: String) -> String {
        var html: [String] = []
        var paragraph: [String] = []

        func flushParagraph() {
            let text = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            paragraph.removeAll(keepingCapacity: true)
            guard !text.isEmpty else { return }
            html.append("<p>\(escape(text))</p>")
        }

        for line in summary.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            if trimmed.hasPrefix("## ") || trimmed.hasPrefix("# ") {
                flushParagraph()
                let title = trimmed.drop(while: { $0 == "#" || $0.isWhitespace })
                html.append("<h2>\(escape(String(title)))</h2>")
                continue
            }
            paragraph.append(trimmed)
        }
        flushParagraph()
        return html.joined()
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func replace(_ regex: NSRegularExpression, in string: String, with template: String) -> String {
        regex.stringByReplacingMatches(
            in: string,
            range: NSRange(string.startIndex..., in: string),
            withTemplate: template
        )
    }
}
