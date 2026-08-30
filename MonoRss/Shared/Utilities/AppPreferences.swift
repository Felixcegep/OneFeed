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

enum AppPreferenceKey {
    static let completedOnboarding = "completedOnboarding"
    static let readerFont = "readerFont"
    static let readerTextSize = "readerTextSize"
}
