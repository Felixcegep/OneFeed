import Foundation
import Testing
@testable import OneFeed

@MainActor
struct SemanticLiveEdgeTests {
    @Test func exactYouTubeIDWinsOverDistantTitles() async {
        let appleTitle = "Apple introduces M6 and M5 Ultra"
        let appleBody = "Apple's M6 and M5 Ultra are built on a 2nm chip and power the new Mac mini."
        let fbiTitle = "FBI investigates ShinyHunters jobs site breach"
        let fbiBody = "Stolen employee data from the jobs site is at the center of the ShinyHunters breach."
        let service = EmbeddingService()
        guard let apple = await service.embed(
            title: appleTitle,
            body: appleBody,
            semanticSummary: "",
            languageCode: "en"
        ) else {
            return
        }
        guard let fbi = await service.embed(
            title: fbiTitle,
            body: fbiBody,
            semanticSummary: "",
            languageCode: "en"
        ) else {
            return
        }

        let remembered = item(
            identityKey: "apple-m6",
            youtubeID: "dQw4w9WgXcQ",
            normalizedURL: "https://www.apple.com/newsroom/2026/09/m6-m5-ultra-mac-mini",
            title: appleTitle,
            body: appleBody,
            sourceTitle: "Apple Newsroom",
            publishedAt: isoDate("2026-09-23T18:00:00Z"),
            embedded: apple
        )
        let incoming = item(
            identityKey: "fbi-shinyhunters-video",
            youtubeID: "dQw4w9WgXcQ",
            normalizedURL: "https://www.cbsnews.com/news/fbi-shinyhunters-jobs-site",
            title: fbiTitle,
            body: fbiBody,
            sourceTitle: "CBS News",
            publishedAt: isoDate("2026-09-23T21:00:00Z"),
            embedded: fbi
        )

        let verdict = SemanticClassifier.classify(item: incoming, against: [remembered])

        #expect(verdict.relationship == .exactDuplicate) // rawValue exactDuplicate
        #expect(verdict.confidence == .certain) // rawValue certain
    }

    @Test func titleOnlyFBIStillMatchesTheFullCBSStory() async {
        let title = Self.fbiTitle
        let service = EmbeddingService()
        guard let memoryVectors = await service.embed(
            title: title,
            body: Self.fbiBody,
            semanticSummary: "",
            languageCode: "en"
        ) else {
            return
        }
        guard let itemVectors = await service.embed(
            title: title,
            body: "",
            semanticSummary: "",
            languageCode: "en"
        ) else {
            return
        }

        let memory = item(
            identityKey: "cbs-fbi-personnel",
            normalizedURL: "https://www.cbsnews.com/news/fbi-personnel-applicant-data",
            title: title,
            body: Self.fbiBody,
            sourceTitle: "CBS News",
            publishedAt: isoDate("2026-09-23T21:00:00Z"),
            embedded: memoryVectors
        )
        let incoming = item(
            identityKey: "pbs-fbi-personnel",
            normalizedURL: "https://www.pbs.org/newshour/nation/fbi-personnel-applicant-data",
            title: title,
            body: "",
            sourceTitle: "PBS News",
            publishedAt: isoDate("2026-09-23T22:00:00Z"),
            embedded: itemVectors
        )

        let verdict = SemanticClassifier.classify(item: incoming, against: [memory])

        #expect(verdict.relationship == .sameStory || verdict.relationship == .related) // rawValue sameStory or related
        #expect(verdict.relationship != .exactDuplicate) // rawValue exactDuplicate
    }

    @Test func frenchFBIStoryIsNotComparedWithEnglish() async {
        let frenchTitle = "Un groupe cybercriminel affirme avoir piraté le FBI"
        let frenchBody = "ShinyHunters revendique le piratage du site de recrutement du FBI et le vol de plusieurs téraoctets de données d'employés et de candidats. Le groupe exige que le FBI retire un bulletin de mai, pas une rançon."
        let service = EmbeddingService()
        guard let french = await service.embed(
            title: frenchTitle,
            body: frenchBody,
            semanticSummary: "",
            languageCode: "fr"
        ) else {
            return
        }
        let english = await service.embed(
            title: Self.fbiTitle,
            body: Self.fbiBody,
            semanticSummary: "",
            languageCode: "en"
        )

        let incoming = item(
            identityKey: "numerama-fbi",
            normalizedURL: "https://www.numerama.com/cyberguerre/2338525",
            title: frenchTitle,
            body: frenchBody,
            sourceTitle: "Numerama",
            publishedAt: isoDate("2026-09-23T16:00:00Z"),
            embedded: french
        )
        let memory = englishMemory(embedded: english)

        let verdict = SemanticClassifier.classify(item: incoming, against: [memory])

        #expect(verdict.relationship == .new) // rawValue new
        #expect(verdict.relationship != .sameStory) // rawValue sameStory
        #expect(verdict.relationship != .nearDuplicate) // rawValue nearDuplicate
    }

    @Test func emptyBodyAndOneWordTitleDoesNotCrash() async {
        let service = EmbeddingService()
        guard let note = await service.embed(
            title: "Note",
            body: "",
            semanticSummary: "",
            languageCode: "en"
        ) else {
            return
        }
        guard let fbi = await service.embed(
            title: Self.fbiTitle,
            body: Self.fbiBody,
            semanticSummary: "",
            languageCode: "en"
        ) else {
            return
        }

        let incoming = item(
            identityKey: "note",
            normalizedURL: "https://example.com/note",
            title: "Note",
            body: "",
            sourceTitle: "Notes",
            publishedAt: isoDate("2026-09-23T12:00:00Z"),
            embedded: note
        )
        let memory = item(
            identityKey: "cbs-fbi-personnel",
            normalizedURL: "https://www.cbsnews.com/news/fbi-personnel-applicant-data",
            title: Self.fbiTitle,
            body: Self.fbiBody,
            sourceTitle: "CBS News",
            publishedAt: isoDate("2026-09-23T21:00:00Z"),
            embedded: fbi
        )

        let verdict = SemanticClassifier.classify(item: incoming, against: [memory])

        #expect(verdict.relationship == .new) // rawValue new
    }

    private static let fbiTitle = "Cybercriminal group claims it stole FBI personnel and applicant data"
    private static let fbiBody = "ShinyHunters says it stole 2 to 3 terabytes of FBI personnel and applicant data through Oracle PeopleSoft on the FBI jobs site."

    private func englishMemory(embedded: EmbeddingService.EmbeddedVectors?) -> SemanticItem {
        if let embedded {
            return item(
                identityKey: "cbs-fbi-personnel",
                normalizedURL: "https://www.cbsnews.com/news/fbi-personnel-applicant-data",
                title: Self.fbiTitle,
                body: Self.fbiBody,
                sourceTitle: "CBS News",
                publishedAt: isoDate("2026-09-23T21:00:00Z"),
                embedded: embedded
            )
        }
        return SemanticItem(
            identityKey: "cbs-fbi-personnel",
            youtubeID: nil,
            normalizedURL: "https://www.cbsnews.com/news/fbi-personnel-applicant-data",
            contentHash: ContentVector.hash(title: Self.fbiTitle, body: Self.fbiBody),
            sourceTitle: "CBS News",
            publishedAt: isoDate("2026-09-23T21:00:00Z"),
            titleVector: nil,
            contentVector: nil,
            embeddingLanguage: "en",
            embeddingRevision: 0,
            hasGeminiSummary: false,
            consumedAt: nil,
            storyClusterID: nil
        )
    }

    private func item(
        identityKey: String,
        youtubeID: String? = nil,
        normalizedURL: String?,
        title: String,
        body: String,
        sourceTitle: String,
        publishedAt: Date?,
        embedded: EmbeddingService.EmbeddedVectors
    ) -> SemanticItem {
        SemanticItem(
            identityKey: identityKey,
            youtubeID: youtubeID,
            normalizedURL: normalizedURL,
            contentHash: ContentVector.hash(title: title, body: body),
            sourceTitle: sourceTitle,
            publishedAt: publishedAt,
            titleVector: embedded.title,
            contentVector: embedded.content,
            embeddingLanguage: embedded.language,
            embeddingRevision: embedded.revision,
            hasGeminiSummary: false,
            consumedAt: nil,
            storyClusterID: nil
        )
    }

    private func isoDate(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: value) ?? Date(timeIntervalSince1970: 0)
    }
}
