import Foundation
import Observation
import ObjectiveC

/// Languages the app UI is translated into (the content-language picker's set).
/// `system` follows the device language (iOS per-app language setting).
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case hindi = "hi"
    case telugu = "te"
    case tamil = "ta"
    case kannada = "kn"
    case malayalam = "ml"

    var id: String { rawValue }

    /// BCP-47 code of the `.lproj` to use; `nil` for `system`.
    var code: String? { self == .system ? nil : rawValue }

    /// Name written in the language itself — always shown in this form so a
    /// reader who can't read the current UI language can still find theirs.
    var nativeName: String {
        switch self {
        case .system: String(localized: "System default")
        case .english: "English"
        case .hindi: "हिन्दी"
        case .telugu: "తెలుగు"
        case .tamil: "தமிழ்"
        case .kannada: "ಕನ್ನಡ"
        case .malayalam: "മലയാളം"
        }
    }

    var englishName: String? {
        switch self {
        case .system: nil
        case .english: "English"
        case .hindi: "Hindi"
        case .telugu: "Telugu"
        case .tamil: "Tamil"
        case .kannada: "Kannada"
        case .malayalam: "Malayalam"
        }
    }
}

/// The user's in-app language choice, applied immediately: SwiftUI text follows
/// `locale` (injected at the root), and `String(localized:)`/`NSLocalizedString`
/// follow the swapped main bundle. The choice is also written to
/// `AppleLanguages` so the next launch starts in it natively.
@MainActor
@Observable
final class AppLanguageStore {
    static let shared = AppLanguageStore()

    private static let defaultsKey = "app_language"

    private(set) var selected: AppLanguage

    /// Bumps on every change; used as a view identity to rebuild the tree.
    private(set) var generation = 0

    var locale: Locale {
        selected.code.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey)
        selected = raw.flatMap(AppLanguage.init(rawValue:)) ?? .system
        Bundle.setOverrideLanguage(selected.code)
    }

    func select(_ language: AppLanguage) {
        guard language != selected else { return }
        selected = language
        UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey)
        if let code = language.code {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        Bundle.setOverrideLanguage(language.code)
        generation += 1
    }
}

// MARK: - Runtime bundle override

private nonisolated(unsafe) var languageBundleKey: UInt8 = 0

private final class OverrideBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = objc_getAssociatedObject(self, &languageBundleKey) as? Bundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    /// Points every lookup through `Bundle.main` at `code`'s `.lproj`
    /// (`nil` restores the device language).
    static func setOverrideLanguage(_ code: String?) {
        if object_getClass(Bundle.main) != OverrideBundle.self {
            object_setClass(Bundle.main, OverrideBundle.self)
        }
        let target: Bundle? = code
            .flatMap { Bundle.main.path(forResource: $0, ofType: "lproj") }
            .flatMap(Bundle.init(path:))
        objc_setAssociatedObject(Bundle.main, &languageBundleKey, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
