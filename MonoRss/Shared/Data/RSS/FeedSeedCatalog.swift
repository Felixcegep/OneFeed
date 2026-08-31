import Foundation

/// The same foldered subscription list as `tiny-rss/seed_feeds.py`, so OneFeed
/// can start with those sources locally instead of waiting on a FreshRSS sync.
enum FeedSeedCatalog {
    struct Entry: Equatable, Sendable {
        let folder: String
        let url: URL
        let title: String
        var contentKind: String {
            url.host()?.contains("youtube.com") == true ? "youtube" : "article"
        }
    }

    static let feeds: [Entry] = [
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
            ("Simon Willison", "https://simonwillison.net/atom/entries/"),
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
            ("Stratechery", "https://stratechery.com/feed/"),
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
    ].flatMap { $0 }

    static let retiredFeedURLs: Set<String> = [
        "https://acephale.substack.com/feed",
        "https://medium.com/feed/art-in-the-21st-century-reflections-provocations",
        "https://bnd.xyz/feed.xml",
        "https://mollyrocket.com/news.xml",
        "https://defiantgatekeeper.substack.com/feed",
        "https://www.youtube.com/feeds/videos.xml?channel_id=UCUq6B9iV6N6N7s5z_j9bZxg",
        "https://www.youtube.com/feeds/videos.xml?channel_id=UCL-WQ0DzCPLh7P4PE4susbQ",
    ]

    private static func folder(_ name: String, _ items: [(String, String)]) -> [Entry] {
        items.compactMap { title, raw in
            URL(string: raw).map { Entry(folder: name, url: $0, title: title) }
        }
    }
}
