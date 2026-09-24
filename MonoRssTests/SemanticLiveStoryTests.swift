import Foundation
import Testing
@testable import OneFeed

struct SemanticLiveStoryTests {
    private struct Fixture {
        var id: String
        var title: String
        var body: String
        var source: String
        var url: String
        var publishedAt: Date
        var languageCode: String?
    }

    @Test @MainActor
    func liveHeadlinesGroupSameStoriesAndRejectFalsePositives() async {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let fixtures = fixtures(formatter)
        let service = EmbeddingService()
        var items: [String: SemanticItem] = [:]
        items.reserveCapacity(fixtures.count)

        for fixture in fixtures {
            guard let embedded = await service.embed(
                title: fixture.title,
                body: fixture.body,
                semanticSummary: "",
                languageCode: nil
            ) else {
                return
            }
            items[fixture.id] = semanticItem(fixture, embedded: embedded)
        }

        let appleChip = items["apple-m6-chip"]!
        let verge = items["verge-m6"]!
        let vergeVerdict = classify(verge, against: [appleChip])
        #expect(
            vergeVerdict.relationship == .sameStory,
            Comment(rawValue: scoreComment(
                "verge-m6",
                "apple-m6-chip",
                vergeVerdict.relationship,
                .sameStory,
                verge,
                appleChip
            ))
        )
        #expect(
            vergeVerdict.relationship != .nearDuplicate,
            Comment(rawValue: scoreComment(
                "verge-m6",
                "apple-m6-chip",
                vergeVerdict.relationship,
                .nearDuplicate,
                verge,
                appleChip
            ))
        )

        let cbs = items["cbs-fbi"]!
        for id in ["pbs-fbi", "ars-fbi", "techcrunch-fbi"] {
            let item = items[id]!
            let verdict = classify(item, against: [cbs])
            #expect(
                verdict.relationship == .sameStory,
                Comment(rawValue: scoreComment(
                    id,
                    "cbs-fbi",
                    verdict.relationship,
                    .sameStory,
                    item,
                    cbs
                ))
            )
        }

        let rumor = items["rumor-july"]!
        let rumorVerdict = classify(rumor, against: [appleChip])
        #expect(
            rumorVerdict.relationship != .sameStory,
            Comment(rawValue: scoreComment(
                "rumor-july",
                "apple-m6-chip",
                rumorVerdict.relationship,
                .sameStory,
                rumor,
                appleChip
            ))
        )
        #expect(
            rumorVerdict.relationship != .exactDuplicate,
            Comment(rawValue: scoreComment(
                "rumor-july",
                "apple-m6-chip",
                rumorVerdict.relationship,
                .exactDuplicate,
                rumor,
                appleChip
            ))
        )
        #expect(
            rumorVerdict.relationship != .nearDuplicate,
            Comment(rawValue: scoreComment(
                "rumor-july",
                "apple-m6-chip",
                rumorVerdict.relationship,
                .nearDuplicate,
                rumor,
                appleChip
            ))
        )

        let explainer = items["explainer-august"]!
        let explainerVerdict = classify(explainer, against: [appleChip])
        #expect(
            explainerVerdict.relationship != .exactDuplicate,
            Comment(rawValue: scoreComment(
                "explainer-august",
                "apple-m6-chip",
                explainerVerdict.relationship,
                .exactDuplicate,
                explainer,
                appleChip
            ))
        )
        #expect(
            explainerVerdict.relationship != .nearDuplicate,
            Comment(rawValue: scoreComment(
                "explainer-august",
                "apple-m6-chip",
                explainerVerdict.relationship,
                .nearDuplicate,
                explainer,
                appleChip
            ))
        )

        let macMini = items["apple-mac-mini"]!
        let macMiniVerdict = classify(macMini, against: [appleChip])
        #expect(
            macMiniVerdict.relationship != .nearDuplicate,
            Comment(rawValue: scoreComment(
                "apple-mac-mini",
                "apple-m6-chip",
                macMiniVerdict.relationship,
                .nearDuplicate,
                macMini,
                appleChip
            ))
        )
        #expect(
            macMiniVerdict.relationship != .exactDuplicate,
            Comment(rawValue: scoreComment(
                "apple-mac-mini",
                "apple-m6-chip",
                macMiniVerdict.relationship,
                .exactDuplicate,
                macMini,
                appleChip
            ))
        )
        #expect(
            macMiniVerdict.relationship != .sameStory,
            Comment(rawValue: scoreComment(
                "apple-mac-mini",
                "apple-m6-chip",
                macMiniVerdict.relationship,
                .sameStory,
                macMini,
                appleChip
            ))
        )

        let crossVerdict = classify(cbs, against: [appleChip])
        #expect(
            crossVerdict.relationship == .new || crossVerdict.relationship == .related,
            Comment(rawValue: scoreComment(
                "cbs-fbi",
                "apple-m6-chip",
                crossVerdict.relationship,
                .new,
                .related,
                cbs,
                appleChip
            ))
        )
    }

    private func classify(_ item: SemanticItem, against memories: [SemanticItem]) -> SemanticVerdict {
        SemanticClassifier.classify(item: item, against: memories)
    }

    private func semanticItem(_ fixture: Fixture, embedded: EmbeddingService.EmbeddedVectors) -> SemanticItem {
        SemanticItem(
            identityKey: fixture.id,
            youtubeID: nil,
            normalizedURL: fixture.url,
            contentHash: ContentVector.hash(title: fixture.title, body: fixture.body),
            sourceTitle: fixture.source,
            publishedAt: fixture.publishedAt,
            titleVector: embedded.title,
            contentVector: embedded.content,
            embeddingLanguage: embedded.language,
            embeddingRevision: embedded.revision,
            hasGeminiSummary: false,
            consumedAt: nil,
            storyClusterID: nil
        )
    }

    private func scoreComment(
        _ leftID: String,
        _ rightID: String,
        _ relationship: ContentRelationship,
        _ compared: ContentRelationship,
        _ left: SemanticItem,
        _ right: SemanticItem
    ) -> String {
        let titleCosine = cosine(left.titleVector ?? [], right.titleVector ?? [])
        let contentCosine = cosine(left.contentVector ?? [], right.contentVector ?? [])
        return """
        \(leftID) vs \(rightID): \(relationship.rawValue) \(compared.rawValue) \
        title cosine \(titleCosine) content cosine \(contentCosine)
        """
    }

    private func scoreComment(
        _ leftID: String,
        _ rightID: String,
        _ relationship: ContentRelationship,
        _ first: ContentRelationship,
        _ second: ContentRelationship,
        _ left: SemanticItem,
        _ right: SemanticItem
    ) -> String {
        let titleCosine = cosine(left.titleVector ?? [], right.titleVector ?? [])
        let contentCosine = cosine(left.contentVector ?? [], right.contentVector ?? [])
        return """
        \(leftID) vs \(rightID): \(relationship.rawValue) \(first.rawValue) \(second.rawValue) \
        title cosine \(titleCosine) content cosine \(contentCosine)
        """
    }

    /// Cosine similarity: dot / (norm * norm). Mismatched or empty vectors score 0.
    private func cosine(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var dot = 0.0
        var leftNorm = 0.0
        var rightNorm = 0.0
        for index in lhs.indices {
            let left = lhs[index]
            let right = rhs[index]
            dot += left * right
            leftNorm += left * left
            rightNorm += right * right
        }
        let denominator = leftNorm.squareRoot() * rightNorm.squareRoot()
        guard denominator > 0 else { return 0 }
        return dot / denominator
    }

    private func fixtures(_ formatter: ISO8601DateFormatter) -> [Fixture] {
        func date(_ value: String) -> Date {
            formatter.date(from: value)!
        }

        let appleChipDate = date("2026-08-25T13:00:00Z")
        let rumorDate = date("2026-07-01T12:00:00Z")
        let explainerDate = date("2026-08-28T16:00:00Z")
        let techCrunchDate = date("2026-09-22T18:40:00Z")
        let fbiDate = date("2026-09-23T21:00:00Z")

        return [
            Fixture(
                id: "apple-m6-chip",
                title: "Apple introduces M6 and M5 Ultra for a big leap in performance and AI compute",
                body: "Apple debuted M6 in the new Mac mini and M5 Ultra in the new Mac Studio. M6 is Apple's first 2-nanometer chip, with a 12-core CPU, 12-core GPU, and a Dual 16-core Neural Engine.",
                source: "Apple Newsroom",
                url: "https://www.apple.com/ca/newsroom/2026/08/apple-introduces-m6-and-m5-ultra",
                publishedAt: appleChipDate,
                languageCode: nil
            ),
            Fixture(
                id: "verge-m6",
                title: "Apple's new M6 chip gets more cores and more AI compute",
                body: "Apple has announced a new M6 chip for Macs, along with an M5 Ultra. The M6 is Apple's first 2nm chip with a 12-core CPU and a Dual 16-core Neural Engine. It will ship in a new Mac mini.",
                source: "The Verge",
                url: "https://www.theverge.com/tech/984118/apple-m6-m5-ultra-chip-mac-mini-studio",
                publishedAt: appleChipDate,
                languageCode: nil
            ),
            Fixture(
                id: "cbs-fbi",
                title: "Cybercriminal group claims it stole FBI personnel and applicant data",
                body: "ShinyHunters claims it breached the FBI and stole 2 to 3 terabytes of data related to FBI and Justice Department workers, using a vulnerability in Oracle PeopleSoft on the FBI jobs site.",
                source: "CBS News",
                url: "https://www.cbsnews.com/news/cybercriminal-group-fbi-data-shinyhunters/",
                publishedAt: fbiDate,
                languageCode: nil
            ),
            Fixture(
                id: "pbs-fbi",
                title: "FBI investigates hackers' claim to have stolen employee data",
                body: "The FBI said it is investigating a criminal hacking group's claims that it stole sensitive data belonging to thousands of agents and applicants and compromised the bureau's jobs website FBIJobs.gov.",
                source: "PBS News",
                url: "https://www.pbs.org/newshour/nation/fbi-investigates-hackers-claim",
                publishedAt: fbiDate,
                languageCode: nil
            ),
            Fixture(
                id: "ars-fbi",
                title: "FBI rushes to investigate if ShinyHunters hack of thousands of employees is real",
                body: "The FBI is investigating claims that thousands of current and former employees' personal data was stolen after hackers exploited a bug on the agency jobs website FBIJobs.gov.",
                source: "Ars Technica",
                url: "https://arstechnica.com/tech-policy/2026/09/fbi-shinyhunters-hack",
                publishedAt: fbiDate,
                languageCode: nil
            ),
            Fixture(
                id: "techcrunch-fbi",
                title: "Hacking group ShinyHunters claims it breached the FBI",
                body: "ShinyHunters says it breached the FBI and stole data on thousands of agents and applicants. The hackers demand the FBI remove a report they say contains false allegations. The jobs site showed it was down for maintenance.",
                source: "TechCrunch",
                url: "https://techcrunch.com/2026/09/22/shinyhunters-fbi",
                publishedAt: techCrunchDate,
                languageCode: nil
            ),
            Fixture(
                id: "rumor-july",
                title: "M6 MacBook Pro coming in late 2026, redesigned M7 model launching in 2027",
                body: "Apple plans to release an updated 14-inch MacBook Pro with an M6 chip in late 2026, then a revamped M7 model in the first half of 2027, Bloomberg reports. The M6 MacBook Pro was finished months ago.",
                source: "MacRumors",
                url: "https://www.macrumors.com/2026/07/01/redesigned-m7-macbook-pro-2027/",
                publishedAt: rumorDate,
                languageCode: nil
            ),
            Fixture(
                id: "explainer-august",
                title: "Which Macs will get an M6 chip and which won't?",
                body: "Apple announced new Mac mini machines this week, and the lower-end models include the first M6 chip. Few Macs will get it. There will be no M6 Pro or M6 Max. A 14-inch MacBook Pro could be updated in October 2026.",
                source: "MacRumors",
                url: "https://www.macrumors.com/2026/08/28/m6-chip-macs/",
                publishedAt: explainerDate,
                languageCode: nil
            ),
            Fixture(
                id: "apple-mac-mini",
                title: "Apple unveils a more powerful Mac mini featuring the all-new M6 and M5 Pro",
                body: "Apple announced the new Mac mini with M6 and M5 Pro. The M6 model delivers up to 4x faster AI performance, 2x faster storage and graphics, and 40 percent faster CPU performance. Pre-order starts today, availability September 22.",
                source: "Apple Newsroom",
                url: "https://www.apple.com/newsroom/2026/08/apple-unveils-mac-mini-m6",
                publishedAt: appleChipDate,
                languageCode: nil
            ),
        ]
    }
}
