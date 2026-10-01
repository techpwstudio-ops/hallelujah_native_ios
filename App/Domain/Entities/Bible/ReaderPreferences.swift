import Foundation

/// A genuinely new, native-only preference — Dart's `bookBgColor`/
/// `bookTextColor` `StorageService` keys are read but never written anywhere
/// in the real app (dead/vestigial), and its font size is hardcoded `18.0`
/// with no picker UI. T54 ships this small feature to honestly satisfy the
/// roadmap's "font size, themes" wording rather than porting non-existent
/// Dart behavior.
enum ReaderTheme: String, Sendable, Equatable, Codable, CaseIterable {
    case light, sepia, dark
}

struct ReaderPreferences: Sendable, Equatable, Codable {
    var fontSize: Double
    var theme: ReaderTheme

    // Named `standard`, not `default` — avoids any ambiguity with the Swift
    // keyword, matching this codebase's other view-model defaults.
    static let standard = ReaderPreferences(fontSize: 18, theme: .light)
    static let fontSizeRange: ClosedRange<Double> = 14...28
    static let fontSizeStep: Double = 2
}
