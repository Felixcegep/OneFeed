import Foundation

/// Resolves browser / system URLs into a subscribe address for Add Source.
///
/// Matches NetNewsWire’s approach: register `feed:` / `feeds:`, normalize to http(s),
/// and also accept OneFeed deep links (`onefeed://subscribe?url=…`, `x-onefeed-feed:…`).
enum IncomingFeedURL {
    /// Returns a website or feed address suitable for `FeedService.addSource`, or `nil`
    /// when the URL is something else (widget reader links, unrelated custom schemes).
    static func subscriptionAddress(from url: URL) -> String? {
        if url.isFileURL { return nil }

        let absolute = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !absolute.isEmpty else { return nil }
        let lower = absolute.lowercased()

        if lower.hasPrefix("feed:") || lower.hasPrefix("feeds:") || lower.hasPrefix("x-onefeed-feed:") {
            return strippingFeedSchemes(absolute)
        }

        if url.scheme?.lowercased() == "onefeed" {
            let host = url.host()?.lowercased()
            if host == "subscribe" || host == "add" {
                return queryValue("url", in: url).map(strippingFeedSchemes)
            }
            // onefeed:https://example.com/atom.xml  (bookmarklet-style)
            if host == nil, absolute.lowercased().hasPrefix("onefeed:") {
                let rest = String(absolute.dropFirst("onefeed:".count))
                if rest.lowercased().hasPrefix("http://") || rest.lowercased().hasPrefix("https://")
                    || rest.lowercased().hasPrefix("feed:") || rest.lowercased().hasPrefix("feeds:") {
                    return strippingFeedSchemes(rest)
                }
            }
        }

        return nil
    }

    /// Converts `feed:` / `feeds:` / `x-onefeed-feed:` forms into an http(s) URL string.
    ///
    /// Handles `feed:https://example.com/atom.xml`, `feed://example.com/atom.xml`,
    /// and bare `feed:example.com/atom.xml` the way NetNewsWire’s `normalizedURL` does.
    static func strippingFeedSchemes(_ input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = s.lowercased()
        var preferHTTPS = false

        if lower.hasPrefix("x-onefeed-feed:") {
            preferHTTPS = true
            s = String(s.dropFirst("x-onefeed-feed:".count))
        } else if lower.hasPrefix("feeds:") {
            preferHTTPS = true
            s = String(s.dropFirst("feeds:".count))
        } else if lower.hasPrefix("feed:") {
            s = String(s.dropFirst("feed:".count))
        }

        if s.hasPrefix("//") {
            s = String(s.dropFirst(2))
        }

        let schemeLower = s.lowercased()
        if schemeLower.hasPrefix("http://") || schemeLower.hasPrefix("https://") {
            return s
        }
        return "\(preferHTTPS ? "https" : "http")://\(s)"
    }

    private static func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
