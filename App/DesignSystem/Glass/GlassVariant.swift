import Foundation

/// The three glass looks every `GlassSurface` supports, mirroring real
/// Liquid Glass's own `Glass.regular` / `Glass.clear` / `.tint(_:)` on iOS 26,
/// and mapped to the material fallback below that.
enum GlassVariant: Sendable, Equatable {
    /// Standard frosted surface — nav bars, tab bar, cards, sheets.
    case regular
    /// Lighter/more see-through — large surfaces over media-rich content
    /// (e.g. the full player background) where the regular variant would
    /// read as too opaque.
    case clear
    /// `regular`, blended with a brand/status color — premium badges,
    /// selected states, alerts.
    case tinted(ColorToken)
}
