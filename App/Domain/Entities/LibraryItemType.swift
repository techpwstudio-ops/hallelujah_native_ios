import Foundation

/// The kinds of content a listener can save to their library that are not
/// their own playlists (`lib/enums/library_item_type.dart`). User playlists are
/// deliberately absent — they have their own ownership endpoints, and folding
/// them in would give one row two sources of truth.
///
/// `apiName` must match the backend `LibraryItemType` enum exactly; it travels
/// in the URL and is the first half of the composite key.
enum LibraryItemType: String, Sendable, Equatable, CaseIterable {
    /// A creator's album or season — both rows of the same table.
    case creatorPlaylist
    /// An admin-curated playlist.
    case companyPlaylist

    var apiName: String { rawValue }

    /// `"<apiName>:<id>"` — what `GET /library/items/ids` returns, so a
    /// creator playlist and a company playlist that share an id never collide.
    func key(for id: String) -> String { "\(apiName):\(id)" }
}

extension Playlist {
    /// The library bucket this playlist saves into.
    var libraryItemType: LibraryItemType {
        switch owner {
        case .company: .companyPlaylist
        case .creator: .creatorPlaylist
        }
    }
}
