import Foundation

/// Ports `Creator`/`getCreatorFromJson` (`lib/models/creator.dart`), unified
/// across the two shapes `SONG_RESPONSE_SHAPE.md` documents separately —
/// "Creator Shape (list view)" (embedded in a `Song`: `image`/
/// `imageVariants`/`name`/`displayName` only) and "Creator Shape (detail
/// view)" (`GET /api/songs/:id`'s `creator`, or a standalone creator-profile
/// fetch: adds `id`/`email`/`bio`/`followersCount`/`followers`). Detail-only
/// fields are simply nil on a list-embedded `Creator` rather than two
/// separate types, same reasoning as `Song`'s own detail-only fields.
///
/// `displayName` is captured here even though Dart's own `$Creator` Realm
/// model drops it entirely — the one place Dart actually reads it is
/// `song.dart`'s `getSongFromJson`, as a fallback source for a SONG's
/// `albumSeasonName` label, not as this type's own preferred label. No
/// general "prefer displayName over name" rule exists in Dart to port, so
/// none is invented here either — callers needing a display string use
/// `name` directly, same as every existing Dart call site does.
struct Creator: Sendable, Equatable, Identifiable {
    let creatorId: String?
    let name: String?
    let displayName: String?
    let image: String?
    let imageVariants: String?
    let bio: String?
    let email: String?
    let mobile: String?
    let username: String?
    let link: String?
    /// The creator's band/group name, distinct from `name` — Dart's `band`.
    let band: String?
    let isActive: Bool?
    let createdAt: Date?
    let updatedAt: Date?

    // Counters — `activeSongsCount`/`activeEpisodeCount`/`activeMusicCount`
    // on the wire (`getCreatorFromJson`'s own field-name split from its
    // `toJson()`, ported as-is rather than "fixed": the request/response
    // shapes for this entity are genuinely asymmetric in Dart already).
    let followersCount: Int?
    let songsCount: Int?
    let episodeCount: Int?
    let musicCount: Int?
    let playlistsCount: Int?
    let albumsCount: Int?
    let seasonsCount: Int?

    /// `followers.isNotEmpty` (`getCreatorFromJson`) — detail-view only;
    /// nil, not false, when the field wasn't present at all (list-embedded
    /// shape) so a caller can tell "not following" from "don't know".
    let isFollowing: Bool?

    /// Falls back to `name`, same reasoning as `Genre.id` — the
    /// list-embedded shape carries no `id` at all.
    var id: String { creatorId ?? name ?? "" }
}
