/// The CDN image-thumbnail sizes the backend actually serves. Confirmed by
/// grepping every `variant: '...'` call site across the whole Flutter app
/// (44 matches under `lib/`) — no size string other than these three appears
/// anywhere, so this is not a guess at the backend's full variant set, it's
/// the complete one actually used.
enum ImageVariant: String, Sendable {
    /// List rows (e.g. `media_artwork.dart`'s default use).
    case sm
    /// Grid / rail cards.
    case md
    /// Full player / hero artwork.
    case lg
}
