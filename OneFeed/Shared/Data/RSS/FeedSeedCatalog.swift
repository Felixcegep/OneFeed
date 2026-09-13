import Foundation

/// Single source of truth for seeded subscriptions: AI reading cadence folders
/// plus the personal tiny-rss topic folders.
enum FeedSeedCatalog {
    /// Bump when the seeded list/folders change so existing installs re-apply.
    static let version = 2

    struct Entry: Equatable, Sendable {
        let folder: String
        let url: URL
        let title: String
        var contentKind: String {
            url.host()?.contains("youtube.com") == true ? "youtube" : "article"
        }
    }

    /// Display / browse order: high-signal cadence first, then topic folders, skim last.
    static let folderOrder: [String] = [
        "Must read",
        "Builders",
        "Philosophy",
        "Programming & Software",
        "Security & Systems",
        "Business",
        "Geopolitics",
        "Fitness",
        "Entertainment",
        "À scanner",
        "Papers",
    ]

    static let feeds: [Entry] = [
        folder("Must read", [
            ("Interconnects AI", "https://www.interconnects.ai/feed"),
            ("Latent Space", "https://www.latent.space/feed"),
            ("Simon Willison", "https://simonwillison.net/atom/entries/"),
            ("IEEE Spectrum Robotics", "https://spectrum.ieee.org/feeds/topic/robotics.rss"),
            ("IEEE Spectrum AI", "https://spectrum.ieee.org/feeds/topic/artificial-intelligence.rss"),
            ("The Robot Report", "https://www.therobotreport.com/feed/"),
            ("OpenAI News", "https://openai.com/news/rss.xml"),
            ("DeepMind", "https://deepmind.google/blog/rss.xml"),
        ]),
        folder("Builders", [
            ("Hugging Face Blog", "https://huggingface.co/blog/feed.xml"),
            ("PlanetScale", "https://planetscale.com/blog/rss.xml"),
            ("GitHub Blog", "https://github.blog/feed/"),
            ("Vercel", "https://vercel.com/atom"),
        ]),
        folder("Philosophy", [
            ("1000-Word Philosophy", "https://1000wordphilosophy.com/feed/"),
            ("Aeon", "https://aeon.co/feed.rss"),
            ("Art Chad", "https://www.youtube.com/feeds/videos.xml?channel_id=UC2Y0KKomVw83JDgjVqVCGzg"),
            ("Astral Codex Ten", "https://www.astralcodexten.com/feed"),
            ("Construction Physics", "https://constructionphysics.substack.com/feed"),
            ("Dynomight", "https://dynomight.net/feed.xml"),
            ("Jonas Čeika", "https://www.youtube.com/feeds/videos.xml?channel_id=UCSkzHxIcfoEr69MWBdo0ppg"),
            ("Julian de Medeiros", "https://www.youtube.com/feeds/videos.xml?channel_id=UCQczEOuFom5rQ8m-X87yQlw"),
            ("Noema", "https://www.noemamag.com/feed/"),
            ("PlasticPills", "https://www.youtube.com/feeds/videos.xml?channel_id=UC9XFvuObhfVUNAGNcH8Y_fw"),
            ("Philosophy of Brains", "https://philosophyofbrains.com/feed"),
            ("The Point", "https://thepointmag.com/feed"),
            ("We're In Hell", "https://www.youtube.com/feeds/videos.xml?channel_id=UCbbsW7_Esx8QZ8PgJ13pGxw"),
        ]),
        folder("Programming & Software", [
            ("Aphyr", "https://aphyr.com/posts.atom"),
            ("CoreDumpped", "https://www.youtube.com/feeds/videos.xml?channel_id=UCGKEMK3s-ZPbjVOIuAV8clQ"),
            ("Dan Luu", "https://danluu.com/atom.xml"),
            ("Marc Brooker", "https://brooker.co.za/blog/rss.xml"),
            ("Metadata", "https://metadata.substack.com/feed"),
            ("MentalOutlaw", "https://www.youtube.com/feeds/videos.xml?channel_id=UC7YOGHUfC1Tb6E4pudI9STA"),
            ("NeetCode", "https://www.youtube.com/feeds/videos.xml?channel_id=UC_mYaQAE6-71rjSN6CeCA-g"),
            ("NeetCodeIO", "https://www.youtube.com/feeds/videos.xml?channel_id=UCevUmOfLTUX9MNGJQKsPdIA"),
            ("No Boilerplate", "https://www.youtube.com/feeds/videos.xml?channel_id=UCUMwY9iS8oMyWDYIe6_RmoA"),
            ("Tailscale", "https://tailscale.com/blog/index.xml"),
        ]),
        folder("Security & Systems", [
            ("Bert Hubert", "https://berthub.eu/articles/index.xml"),
            ("Cloudflare Networking", "https://blog.cloudflare.com/tag/networking/rss/"),
            ("Julia Evans", "https://jvns.ca/atom.xml"),
            ("Rachel by the Bay", "https://rachelbythebay.com/w/atom.xml"),
            ("Schneier on Security", "https://www.schneier.com/feed/atom/"),
            ("Trail of Bits", "https://blog.trailofbits.com/feed/"),
        ]),
        folder("Business", [
            ("Bits about Money", "https://www.bitsaboutmoney.com/archive/rss/"),
            ("Benjamin", "https://www.youtube.com/feeds/videos.xml?channel_id=UC8qAOyPgCtqb_ESbhFGxv9w"),
            ("How Money Works", "https://www.youtube.com/feeds/videos.xml?channel_id=UCkCGANrihzExmu9QiqZpPlQ"),
            ("Works in Progress", "https://worksinprogress.co/rss.xml"),
        ]),
        folder("Geopolitics", [
            ("7 jours sur Terre", "https://www.youtube.com/feeds/videos.xml?channel_id=UCWgjYWqcxqss3vFqYVvaI0Q"),
            ("CHAQUE JOUR SUR TERRE", "https://www.youtube.com/feeds/videos.xml?channel_id=UCPHLvIgDTxzYwSiXDfBYhsQ"),
            ("JREG", "https://www.youtube.com/feeds/videos.xml?channel_id=UCGSGPehp0RWfca-kENgBJ9Q"),
        ]),
        folder("Fitness", [
            ("Barbell Medicine", "https://www.barbellmedicine.com/feed"),
            ("Stronger by Science", "https://www.strongerbyscience.com/articles/feed/feed"),
            ("Vintagelifts", "https://www.youtube.com/feeds/videos.xml?channel_id=UCnv36GcqMDfPcmDFMfPne8A"),
        ]),
        folder("Entertainment", [
            ("Gigguk", "https://www.youtube.com/feeds/videos.xml?channel_id=UC7dF9qfBMXrSlaaFFDvV_Yg"),
            ("Gotabor", "https://www.youtube.com/feeds/videos.xml?channel_id=UCsj6CSOcjaQmsZtKvZUiYXw"),
            ("ProfessorViral", "https://www.youtube.com/feeds/videos.xml?channel_id=UCqJ5EkPzmVHTTrrHtmgWeeg"),
        ]),
        folder("À scanner", [
            ("TechCrunch AI", "https://techcrunch.com/category/artificial-intelligence/feed/"),
            ("The Verge AI", "https://www.theverge.com/rss/ai-artificial-intelligence/index.xml"),
            ("Hacker News", "https://hnrss.org/frontpage"),
        ]),
        folder("Papers", [
            ("arXiv cs.RO", "https://rss.arxiv.org/rss/cs.RO"),
            ("arXiv cs.AI", "https://rss.arxiv.org/rss/cs.AI"),
            ("arXiv cs.LG", "https://rss.arxiv.org/rss/cs.LG"),
        ]),
    ].flatMap { $0 }

    static let retiredFeedURLs: Set<String> = [
        "https://acephale.substack.com/feed",
        "https://medium.com/feed/art-in-the-21st-century-reflections-provocations",
        "https://bnd.xyz/feed.xml",
        "https://mollyrocket.com/news.xml",
        "https://defiantgatekeeper.substack.com/feed",
        "https://www.youtube.com/feeds/videos.xml?channel_id=UCUq6B9iV6N6N7s5z_j9bZxg",
        "https://www.youtube.com/feeds/videos.xml?channel_id=UCL-WQ0DzCPLh7P4PE4susbQ",
        "https://stratechery.com/feed/",
    ]

    static func isRetired(title: String, url: URL? = nil) -> Bool {
        if let url, retiredFeedURLs.contains(url.absoluteString) { return true }
        return title.range(of: "stratechery", options: .caseInsensitive) != nil
    }

    static func opmlDocument() -> OPMLDocument {
        var body = ""
        for folderName in folderOrder {
            let items = feeds.filter { $0.folder == folderName }
            guard !items.isEmpty else { continue }
            body += "  <outline text=\"\(escape(folderName))\" title=\"\(escape(folderName))\">\n"
            for entry in items {
                body += "    <outline type=\"rss\" text=\"\(escape(entry.title))\" title=\"\(escape(entry.title))\" xmlUrl=\"\(escape(entry.url.absoluteString))\"/>\n"
            }
            body += "  </outline>\n"
        }
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
        <head>
          <title>OneFeed · All Sources</title>
          <ownerName>OneFeed</ownerName>
        </head>
        <body>
        \(body.trimmingCharacters(in: .newlines))
        </body>
        </opml>
        """
        return OPMLDocument(data: Data(xml.utf8))
    }

    private static func folder(_ name: String, _ items: [(String, String)]) -> [Entry] {
        items.compactMap { title, raw in
            URL(string: raw).map { Entry(folder: name, url: $0, title: title) }
        }
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
