import Foundation

/// GET share-link-minting routes — `deep_link_service.dart`'s `create()`
/// family (`create(songId)`, `createCreatorLink`, `sharePlaylist`,
/// `createCompanyPlaylistLink`). Each mirrors `bibleVerseShare(id:)`
/// (`BibleEndpoint.swift`) and `verseOfDayShare(id:)`
/// (`Endpoint+VerseOfDay.swift`): same `{data: {link}}` envelope, different
/// content type. No plain creator-playlist (non-company) share route exists
/// on the backend/Dart side either — `end_points.dart` only ever defines
/// `shareUserPlaylistApi`/`shareCompanyPlaylistApi`, never a bare
/// `sharePlaylistApi` — so none is added here.
extension Endpoint {
    /// `end_points.dart`'s `shareSongApi`: `GET /song/:id/share`.
    static func songShare(id: String) -> Endpoint {
        .get("/song/\(id)/share")
    }

    /// `end_points.dart`'s `shareCreatorApi`: `GET /creators/:id/share`.
    static func creatorShare(id: String) -> Endpoint {
        .get("/creators/\(id)/share")
    }

    /// `end_points.dart`'s `shareUserPlaylistApi`: `GET /library/user-playlist/:id/share`.
    static func userPlaylistShare(id: String) -> Endpoint {
        .get("/library/user-playlist/\(id)/share")
    }

    /// `end_points.dart`'s `shareCompanyPlaylistApi`: `GET /company-playlist/:id/share`.
    static func companyPlaylistShare(id: String) -> Endpoint {
        .get("/company-playlist/\(id)/share")
    }
}
