import Foundation

/// What a song's related content is expressed in (`RelatedItemKind`,
/// `lib/models/related_item.dart`): music is browsed through curated company
/// playlists, episodes through the shows (creators) that publish them. The
/// server decides; the app branches.
enum RelatedItemKind: Sendable, Equatable {
    case playlist
    case creator

    init(wire value: String?) {
        self = value == "creator" ? .creator : .playlist
    }
}

/// One entry of `GET /song/:id/related` (`RelatedItem`).
struct RelatedItem: Sendable, Equatable, Identifiable {
    let kind: RelatedItemKind
    let id: String
    let title: String
    /// Why the backend surfaced this: a code, not display text.
    let reason: String?
    let image: String?
    let imageVariants: String?

    /// `reasonLabel`: falls back to a neutral label rather than leaking a raw
    /// code when the backend adds a signal the app predates.
    var reasonLabel: String {
        switch kind {
        case .playlist:
            switch reason {
            case "features_this_song": "Features this song"
            case "same_artist": "Same artist"
            case "same_genre": "Similar sound"
            default: "More like this"
            }
        case .creator:
            switch reason {
            case "same_genre": "Similar shows"
            case "same_language": "Same language"
            case "popular": "Popular show"
            default: "More like this"
            }
        }
    }
}

/// A related-content response: the `kind` every item shares plus the items.
/// Kind rides on the envelope so an empty result still says which mode it was
/// in (`RelatedContent`).
struct RelatedContent: Sendable, Equatable {
    let kind: RelatedItemKind
    let items: [RelatedItem]

    static let empty = RelatedContent(kind: .playlist, items: [])

    var isEmpty: Bool { items.isEmpty }
}
