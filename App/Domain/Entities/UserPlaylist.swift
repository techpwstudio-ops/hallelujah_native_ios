import Foundation

/// A signed-in user's own library playlist (`UserPlaylist`,
/// `lib/models/user_playlist.dart`) — `Playlist.swift`'s own doc comment
/// already deferred this here. Genuinely a different shape from `Playlist`:
/// singly user-owned (`ownerUserID`, not `PlaylistOwner`), no `rank` (that's
/// `CompanyPlaylist`'s curated ordering, not applicable here).
///
/// No `isOwner`/`isFollowing`/`isFollowed` stored here even though
/// `userPlaylist.controller.js`'s list endpoint (`getUserPlaylists`) sends
/// computed flags of exactly that shape: confirmed directly that its single-
/// fetch sibling (`getUserPlaylist`/`getSongsByUserPlaylist`) sends neither
/// flag, only the raw `userId` column, and that the list endpoint's own
/// followed-branch uses the inconsistent key `isFollowed` (not
/// `isFollowing`) — a real backend naming bug. Rather than trust a flag that
/// isn't reliably present, `ownerUserID` is kept raw and ownership is always
/// derived client-side (`isOwned(by:)`) against `CurrentUserStore`.
struct UserPlaylist: Sendable, Equatable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let image: String?
    let imageVariants: String?
    let visibility: String?
    let songsCount: Int?
    let duration: Int?
    let ownerUserID: String?
    let createdAt: Date?
    /// `UserPlaylist.songs` (ids of the songs it holds) — the add-to-playlist
    /// sheet reads it to show add vs remove per row. Empty when the endpoint
    /// omits `songs`.
    var songIDs: [String] = []
    /// `UserPlaylist.adminName` (`user.fName`): the owner's first name.
    var ownerName: String? = nil

    func isOwned(by currentUserID: String?) -> Bool {
        guard let currentUserID, let ownerUserID else { return false }
        return ownerUserID == currentUserID
    }
}
