import Foundation

extension VideoQuality {
    /// The name in the Settings row's sentence and the player's menu.
    var displayName: String {
        switch self {
        case .auto: String(localized: "Auto")
        case .p480: String(localized: "480p")
        case .p720: String(localized: "720p HD")
        case .p1080: String(localized: "1080p Full HD")
        case .original: String(localized: "Original")
        }
    }
}
