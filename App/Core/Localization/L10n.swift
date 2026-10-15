import Foundation

/// Runtime lookup for strings that reach the UI as a plain `String` (toasts,
/// view-model messages) where the compiler cannot extract a key. English text is
/// the key (`Localizable.xcstrings`, development language `en`); a miss — e.g. a
/// server-supplied message — returns the text unchanged.
///
/// Prefer, in order: SwiftUI literals (`Text("Save")`, auto-localised);
/// `String(localized: "Save")` when a `String` is needed (interpolation is
/// allowed: `String(localized: "Removed from \(name)")`); `L10n.tr("Save")` only
/// for a fixed literal that must stay a plain `String` argument.
enum L10n {
    static func tr(_ key: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: .main, value: key, comment: "")
    }
}
