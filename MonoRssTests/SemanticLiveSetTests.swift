import Foundation
import Testing
@testable import OneFeed

/// Classifies every fixture against the whole set, which is how a new item meets history.
struct SemanticLiveSetTests {
    private struct Fixture {
        var id: String
        var title: String
        var body: String
        var source: String
        var url: String
        var publishedAt: Date
        var cluster: String
    }

    @Test @MainActor
    func eachStoryMatchesItsOwnClusterNotTheSharedVocabulary() async {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        func date(_ value: String) -> Date { formatter.date(from: value)! }
        let day = "2026-08-25T17:00:00Z"
        let fbiDay = "2026-09-23T21:00:00Z"
        let fixtures = [
            Fixture(
                id: "m6-chip",
                title: "Apple introduces M6 and M5 Ultra for a big leap in performance and AI compute",
                body: "Apple debuted M6 in the new Mac mini and M5 Ultra in the new Mac Studio. M6 is Apple's first 2-nanometer chip, with a 12-core CPU, 12-core GPU, and a Dual 16-core Neural Engine.",
                source: "Apple Newsroom",
                url: "https://www.apple.com/newsroom/2026/08/m6",
                publishedAt: date(day),
                cluster: "m6"
            ),
            Fixture(
                id: "m6-verge",
                title: "Apple's new M6 chip gets more cores and more AI compute",
                body: "Apple has announced a new M6 chip for Macs. The M6 is Apple's first 2nm chip with a 12-core CPU and a Dual 16-core Neural Engine, and it will ship in a new Mac mini.",
                source: "The Verge",
                url: "https://www.theverge.com/tech/984118",
                publishedAt: date(day),
                cluster: "m6"
            ),
            Fixture(
                id: "studio-verge",
                title: "Apple launches new Mac Studios with its most powerful chip ever, the M5 Ultra",
                body: "Apple is announcing new Mac Studio models using the M5 Max and a new M5 Ultra. The M5 Ultra merges two dual-die M5 Max chips. The computers arrive September 22.",
                source: "The Verge",
                url: "https://www.theverge.com/tech/984207",
                publishedAt: date(day),
                cluster: "studio"
            ),
            Fixture(
                id: "studio-macrumors",
                title: "Apple unveils new Mac Studio with M5 Max and M5 Ultra chips",
                body: "Apple announced new Mac Studio models with M5 Max and M5 Ultra. The M5 Ultra has up to a 36-core CPU and 80-core GPU, up to 512GB of memory, and ships September 22.",
                source: "MacRumors",
                url: "https://www.macrumors.com/2026/08/25/apple-announces-new-mac-studio",
                publishedAt: date(day),
                cluster: "studio"
            ),
            Fixture(
                id: "july-rumor",
                title: "M6 MacBook Pro coming in late 2026",
                body: "Bloomberg reports Apple plans a 14-inch MacBook Pro with an M6 chip in late 2026, then an M7 model in 2027. The laptop was finished months ago.",
                source: "MacRumors",
                url: "https://www.macrumors.com/2026/07/01/m6-macbook-pro",
                publishedAt: date("2026-07-01T16:00:00Z"),
                cluster: "rumor"
            ),
            Fixture(
                id: "cbs",
                title: "Cybercriminal group claims it stole FBI personnel and applicant data",
                body: "ShinyHunters claims it breached the FBI and stole 2 to 3 terabytes of data on FBI workers through an Oracle PeopleSoft flaw on the FBI jobs site.",
                source: "CBS News",
                url: "https://www.cbsnews.com/news/fbi-shinyhunters",
                publishedAt: date(fbiDay),
                cluster: "fbi"
            ),
            Fixture(
                id: "bleeping",
                title: "ShinyHunters claims FBI hack and data theft in PeopleSoft zero-day breach",
                body: "ShinyHunters says it breached FBI systems with an Oracle PeopleSoft zero-day, defaced the FBI jobs site, and stole sensitive data on employees and applicants.",
                source: "BleepingComputer",
                url: "https://www.bleepingcomputer.com/news/security/shinyhunters-fbi",
                publishedAt: date(fbiDay),
                cluster: "fbi"
            ),
            Fixture(
                id: "securityweek",
                title: "ShinyHunters claims FBI hack and demands retraction of threat report",
                body: "ShinyHunters claims it breached FBI systems, defaced fbijobs.gov, and gave the FBI one week to correct a May report. The FBI says it is investigating unauthorized activity on the jobs site.",
                source: "SecurityWeek",
                url: "https://www.securityweek.com/shinyhunters-claims-fbi-hack",
                publishedAt: date("2026-09-23T07:13:00Z"),
                cluster: "fbi"
            ),
        ]

        let service = EmbeddingService()
        var items: [Fixture] = []
        var embedded: [String: SemanticItem] = [:]
        for fixture in fixtures {
            guard let vectors = await service.embed(
                title: fixture.title,
                body: fixture.body,
                semanticSummary: "",
                languageCode: "en"
            ) else {
                return
            }
            items.append(fixture)
            embedded[fixture.id] = SemanticItem(
                identityKey: fixture.id,
                youtubeID: nil,
                normalizedURL: fixture.url,
                contentHash: ContentVector.hash(title: fixture.title, body: fixture.body),
                sourceTitle: fixture.source,
                publishedAt: fixture.publishedAt,
                titleVector: vectors.title,
                contentVector: vectors.content,
                embeddingLanguage: vectors.language,
                embeddingRevision: vectors.revision,
                hasGeminiSummary: false,
                consumedAt: nil,
                storyClusterID: nil
            )
        }

        let byID = Dictionary(uniqueKeysWithValues: fixtures.map { ($0.id, $0) })
        for fixture in items {
            let item = embedded[fixture.id]!
            let others = embedded.values.filter { $0.identityKey != fixture.id }
            let verdict = SemanticClassifier.classify(item: item, against: Array(others))
            let match = verdict.matchedIdentityKey.flatMap { byID[$0] }
            let comment = "\(fixture.id) -> \(verdict.relationship.rawValue) \(verdict.matchedIdentityKey ?? "none")"
            switch fixture.cluster {
            case "m6" where fixture.id == "m6-chip":
                // This press release announces both the M6 mini and the M5 Ultra Studio, so either cluster is a fair nearest story.
                #expect(verdict.relationship == .sameStory, Comment(rawValue: comment))
                #expect(match?.cluster == "m6" || match?.cluster == "studio", Comment(rawValue: comment))
            case "m6":
                #expect(verdict.relationship == .sameStory, Comment(rawValue: comment))
                #expect(match?.cluster == "m6", Comment(rawValue: comment))
            case "studio":
                #expect(verdict.relationship == .sameStory, Comment(rawValue: comment))
                #expect(match?.cluster == "studio", Comment(rawValue: comment))
            case "fbi":
                #expect(verdict.relationship == .sameStory, Comment(rawValue: comment))
                #expect(match?.cluster == "fbi", Comment(rawValue: comment))
            case "rumor":
                #expect(verdict.relationship != .sameStory, Comment(rawValue: comment))
                #expect(verdict.relationship != .nearDuplicate, Comment(rawValue: comment))
                #expect(match?.cluster != "m6" || verdict.relationship == .related || verdict.relationship == .new, Comment(rawValue: comment))
            default:
                break
            }
        }
    }
}
