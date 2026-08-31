import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum ReaderFontChoice: String, CaseIterable, Identifiable {
    case sans
    case serif
    case mono

    var id: Self { self }
    var label: String { rawValue.capitalized }
}

enum ReaderTextSize: String, CaseIterable, Identifiable {
    case small
    case standard
    case large

    var id: Self { self }
    var label: String { self == .standard ? "Default" : rawValue.capitalized }
    var basePoints: CGFloat {
        switch self { case .small: 17; case .standard: 19; case .large: 22 }
    }
    var points: CGFloat {
        #if canImport(UIKit)
        UIFontMetrics(forTextStyle: .body).scaledValue(for: basePoints)
        #else
        basePoints
        #endif
    }
}

enum ArticleRetentionChoice: Int, CaseIterable, Identifiable {
    case threeDays = 3
    case sevenDays = 7
    case fourteenDays = 14
    case thirtyDays = 30
    case forever = 0

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .threeDays: "3 days"
        case .sevenDays: "7 days"
        case .fourteenDays: "14 days"
        case .thirtyDays: "30 days"
        case .forever: "Forever"
        }
    }
}

enum AppPreferenceKey {
    static let completedOnboarding = "completedOnboarding"
    static let readerFont = "readerFont"
    static let readerTextSize = "readerTextSize"
    static let didSeedTinyRSSCatalog = "didSeedTinyRSSCatalog"
    static let articleRetentionDays = "articleRetentionDays"
    static let lastSuccessfulRefresh = "lastSuccessfulRefresh"
}
