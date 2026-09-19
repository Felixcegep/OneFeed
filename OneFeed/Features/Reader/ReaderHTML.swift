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

    private static func replace(_ regex: NSRegularExpression, in string: String, with template: String) -> String {
        regex.stringByReplacingMatches(
            in: string,
            range: NSRange(string.startIndex..., in: string),
            withTemplate: template
        )
    }
}
