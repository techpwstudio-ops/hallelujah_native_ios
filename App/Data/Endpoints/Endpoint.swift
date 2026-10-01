import Foundation

/// A request template. Mirrors `lib/utils/end_points.dart` — add a case here
/// as each feature needs a route, rather than porting the whole Dart file
/// up front.
struct Endpoint: Sendable {
    enum Base: Sendable {
        case api
        case proxy
    }

    let base: Base
    let path: String
    let method: HTTPMethod

    static func get(_ path: String, base: Base = .api) -> Endpoint {
        Endpoint(base: base, path: path, method: .get)
    }

    static func post(_ path: String, base: Base = .api) -> Endpoint {
        Endpoint(base: base, path: path, method: .post)
    }

    static func patch(_ path: String, base: Base = .api) -> Endpoint {
        Endpoint(base: base, path: path, method: .patch)
    }

    static func delete(_ path: String, base: Base = .api) -> Endpoint {
        Endpoint(base: base, path: path, method: .delete)
    }
}

extension Endpoint {
    /// Unauthenticated IP -> country lookup. `end_points.dart:60`.
    static let geoCountry = Endpoint.get("/geo/country")

    /// `end_points.dart:50` comments this `// GET`, but `session.dart`
    /// actually calls it with `DioApi.instance.postData(...)` — the comment
    /// is stale, this follows the real call site.
    static let refreshToken = Endpoint.post("/auth/token/refresh")

    /// `validateDeepLinkApi` (`end_points.dart`): `'/deep-link/$id/validate'`.
    /// The one inbound deep-link endpoint T18 needs — every `share*Api`
    /// sibling in that file is outbound link creation, owned by whichever
    /// milestone builds that content type's share UI.
    static func validateDeepLink(code: String) -> Endpoint {
        .get("/deep-link/\(code)/validate")
    }

    // MARK: Auth (T20) — `end_points.dart`, the unified OTP transport
    // (`lib/features/authentication/data/auth_otp_service.dart`).

    static let authOTPSend = Endpoint.post("/auth/otp/send")
    static let authOTPResend = Endpoint.post("/auth/otp/resend")
    static let authOTPVerify = Endpoint.post("/auth/otp/verify")

    /// `authUserApi` (`end_points.dart:47`) — `/users/me`.
    static let currentUser = Endpoint.get("/users/me")

    /// `EndPoints.verifySocialAuth` (T23) — Google/Apple sign-in
    /// verification, `_checkSocialAuth` (`lib/blocs/auth/bloc.dart`).
    static let authOAuthVerify = Endpoint.post("/auth/oauth/verify")

    /// `userDataUpdateApi` (`end_points.dart:81`) comments this
    /// `// PUT/PATCH`, but `AccountSetupPageState._submitDetails` (T24)
    /// actually calls it with `DioApi.instance.postData(...)` — same
    /// stale-comment-vs-real-verb mismatch as `refreshToken`/`logout` above.
    static let userProfileSave = Endpoint.post("/users/profile/save")

    /// `logOutApi` (`end_points.dart:95`) comments this `// POST`, but the
    /// one real call site (`session.dart`'s `logout()`) uses
    /// `DioApi.instance.getData(...)` — same stale-comment-vs-real-verb
    /// mismatch already flagged above for `refreshToken`.
    static let logout = Endpoint.get("/user/logout")

    /// `getLanguagesApi` (`end_points.dart:161`) — `/languages`.
    static let languages = Endpoint.get("/languages")

    /// `updateUserLanguagesApi` (`end_points.dart:83`) comments this
    /// `// PUT/PATCH`, but `LanguageNotifier.saveLanguages`
    /// (`lib/providers/language_provider.dart`) actually calls it with
    /// `DioApi.instance.postData(...)` — same stale-comment-vs-real-verb
    /// mismatch already flagged repeatedly above.
    static let saveLanguages = Endpoint.post("/user/save/languages")

    // MARK: Home V2 (T28) — `docs/HOME_V2_API.md` (backend repo), the
    // authoritative spec for this contract; the app's own
    // `getHomeV2*Api` helpers (`end_points.dart:110-130`) just build these
    // same three paths.

    /// §3.1 — the manifest. `withSections` front-loads the first N rails'
    /// content into this same response (capped at 6 server-side); `0` (the
    /// default) is the old byte-identical shape with no `hydrated`/
    /// `emptyUiIds`.
    static func homeLayout(type: HomeContentType, withSections: Int = 6) -> Endpoint {
        .get("/v2/home/layout/\(type.rawValue)?withSections=\(withSections)")
    }

    /// §3.3 — a window of rails hydrated together, `limit` capped at 6
    /// server-side. The background prefetch-sweep path.
    static func homeFeed(type: HomeContentType, offset: Int, limit: Int = 6) -> Endpoint {
        .get("/v2/home/feed/\(type.rawValue)?offset=\(offset)&limit=\(limit)")
    }

    /// §3.2 — one rail, on demand. The fallback for a placeholder the
    /// prefetch sweep hasn't reached yet, and the only path for `page=2+`.
    static func homeSection(type: HomeContentType, uiId: String, page: Int = 1) -> Endpoint {
        .get("/v2/home/section/\(type.rawValue)/\(uiId)?page=\(page)")
    }

    // MARK: Creator profile (T30) — `end_points.dart:162-168`.

    /// `getCreatorApi` — `/creator/:id`.
    static func creatorDetail(id: String) -> Endpoint {
        .get("/creator/\(id)")
    }

    /// `getCreatorSongsApi` — `/creators/songs/:id`. `page`/`type` travel as
    /// query params, same as Dart's own `getData(url, body: {...})` (its
    /// `body` for a GET request is query params — see `DioService.getData`'s
    /// own doc comment).
    static func creatorSongs(id: String, type: HomeContentType, page: Int) -> Endpoint {
        .get("/creators/songs/\(id)?page=\(page)&type=\(type.rawValue)")
    }

    /// `getCreatorPlaylistsApi` — `/creators/playlists/:id`.
    static func creatorPlaylists(id: String, type: HomeContentType, page: Int) -> Endpoint {
        .get("/creators/playlists/\(id)?page=\(page)&type=\(type.rawValue)")
    }

    /// `followCreatorApi` — `/creators/follow`. Real call site
    /// (`lib/blocs/favourite/bloc.dart`'s `attachCreators`) POSTs `{detach, ids}`.
    static let followCreators = Endpoint.post("/creators/follow")

    /// `unfollowCreatorApi` — `/creators/un-follow`. `end_points.dart`
    /// comments this `// DELETE`, but the one real call site
    /// (`favourite/bloc.dart`'s `detachCreator`) POSTs `{ids}` — same
    /// stale-comment-vs-real-verb mismatch already flagged repeatedly above
    /// for other endpoints in this file.
    static let unfollowCreators = Endpoint.post("/creators/un-follow")

    // MARK: Playlist songs (T29) — `end_points.dart`'s `getPlaylistSongs`/
    // `getCompanyPlaylistSongs`, the two endpoints `Playlist.owner` (T27)
    // dispatches between.

    /// `getPlaylistSongs(id) => '/playlist/$id/songs'` — a creator-owned
    /// playlist/album/season (`PlaylistSongPage`, `album_songs_page.dart`).
    static func playlistSongs(id: String, page: Int) -> Endpoint {
        .get("/playlist/\(id)/songs?page=\(page)")
    }

    /// `getCompanyPlaylistSongs(id) => '/company-playlist/$id/songs'`
    /// (`CompanyPlaylistSongsPage`, `company_playlist_songs_page.dart`).
    static func companyPlaylistSongs(id: String, page: Int) -> Endpoint {
        .get("/company-playlist/\(id)/songs?page=\(page)")
    }

    // MARK: Analytics (T38) — `end_points.dart:299`'s `sendAnalyticsDataApi`.

    /// `sendAnalyticsDataApi = '/analytics/track'` (`end_points.dart:299`) —
    /// the batch upload `AnalyticsSyncEngine` posts a `{playbackSessions,
    /// playbackEvents, device, force}` body to. `ANALYTICS_PAYLOAD.md`'s own
    /// header documents this as `POST /api/sendAnalyticsData`, but that's
    /// stale — `tracking_event_sync_service.dart:149,263` both call through
    /// `EndPoints.sendAnalyticsDataApi`, the real string above, confirmed
    /// against the constant itself rather than the doc's prose.
    static let sendAnalyticsData = Endpoint.post("/analytics/track")

    // MARK: Browse (T42)

    /// `getInitDataApi` (`end_points.dart:105`) → `/dashboard/init`. Ported
    /// only for its `genres` slice here — `getUserAppInitData`
    /// (`dashboard.controller.js`) returns a full app-bootstrap payload, but
    /// `DashboardInitGenresDTO` below decodes just the one key this repo
    /// needs. `genre.controller.js` exports no dedicated single-genre-list
    /// endpoint, so this doubles as both the browse grid's source and (by
    /// client-side filter) a single genre's own name/image lookup.
    static let dashboardInit = Endpoint.get("/dashboard/init")

    /// `getSongsByGenre` (`end_points.dart:169`) → `/genre/songs/:genreId`,
    /// mounted under the authenticated router
    /// (`dashboard.routes.js:205`) — not the separate public
    /// `/web/browse/genre/songs/:genreId` (`publicBrowse.routes.js`), which
    /// this app never calls. `getGenreSongs` (`genre.controller.js:102-172`)
    /// paginates with the same `{meta: {count, page, perPage, totalPages},
    /// data}` shape as `CreatorSongsResponseDTO` (no `hasMore` field).
    static func genreSongs(id: String, page: Int) -> Endpoint {
        .get("/genre/songs/\(id)?page=\(page)")
    }

    // MARK: Library (T43) — `library.controller.js`'s `getLibraryCount`/
    // `getLibraryItems`, mounted directly on the authenticated dashboard
    // router (`dashboard.routes.js:220,224`) with no extra path prefix
    // beyond `AppConfiguration.apiBaseURL`'s own baked-in `/api`.

    /// `getLibraryCount` — `/library/content/count/:type`.
    static func libraryCount(type: HomeContentType) -> Endpoint {
        .get("/library/content/count/\(type.rawValue)")
    }

    /// `getLibraryItems` — `/library/items`, `page`/`type` as query params.
    static func libraryItems(type: HomeContentType, page: Int) -> Endpoint {
        .get("/library/items?page=\(page)&type=\(type.rawValue)")
    }

    // MARK: Favourites (T44) — `songs.controller.js`'s `getFavoriteSongs`/
    // `toggleSongFavorite`, `creators.controller.js`'s `getFavoriteCreators`.

    /// `getFavoriteSongs` — `/song/favorite?type=&page=`. Defaults
    /// server-side to `type=all`/`page=1`/`perPage=10` if omitted, but every
    /// call site here sends `type`/`page` explicitly.
    static func favoriteSongs(type: HomeContentType, page: Int) -> Endpoint {
        .get("/song/favorite?type=\(type.rawValue)&page=\(page)")
    }

    /// `toggleSongFavorite` — `/song/toggle/favorite/:songId?value=`. Every
    /// response branch (favorite-create, favorite-already-exists,
    /// unfavorite-success, unfavorite-already-absent) carries a non-song-
    /// shaped payload or none at all (confirmed directly against the
    /// controller) — callers key off the HTTP status only.
    static func toggleSongFavorite(songId: String, isFavorited: Bool) -> Endpoint {
        .get("/song/toggle/favorite/\(songId)?value=\(isFavorited)")
    }

    /// `getFavoriteCreators` — `/creators/favorite?page=&type=`. `perPage`
    /// is fixed server-side at 30 and never sent as a param (confirmed
    /// directly against the controller).
    static func favoriteCreators(type: HomeContentType, page: Int) -> Endpoint {
        .get("/creators/favorite?page=\(page)&type=\(type.rawValue)")
    }

    // MARK: User playlists (T45) — `userPlaylist.controller.js`, routes
    // confirmed directly against `dashboard.routes.js:228-238`. Reorder,
    // the song-menu "add to playlist" sheet, visibility toggle, follow/
    // unfollow, share, and add-to-queue are all out of scope for T45 — see
    // its own status-log entry — so `togglePlaylistVisibility`/
    // `togglePlaylistFollowing`/`shareUserPlaylist` have no endpoint here.

    /// `getUserPlaylists` — `/library/user-playlist?page=`. `perPage`
    /// defaults server-side to 10 and is never sent, same precedent as
    /// `favoriteCreators` above.
    static func userPlaylists(page: Int) -> Endpoint {
        .get("/library/user-playlist?page=\(page)")
    }

    /// `createUserPlaylist` — `POST /library/user-playlist`, body
    /// `{title, songId?}` sent by the caller.
    static let createUserPlaylist = Endpoint.post("/library/user-playlist")

    /// `updateUserPlaylist` (rename only — the controller reads just
    /// `title` from the body) — `PATCH /library/user-playlist/:id`.
    static func renameUserPlaylist(id: String) -> Endpoint {
        .patch("/library/user-playlist/\(id)")
    }

    /// `getUserPlaylist` — `/library/user-playlist/:id`.
    static func userPlaylist(id: String) -> Endpoint {
        .get("/library/user-playlist/\(id)")
    }

    /// `deleteUserPlaylist` — `DELETE /library/user-playlist/:id`.
    static func deleteUserPlaylist(id: String) -> Endpoint {
        .delete("/library/user-playlist/\(id)")
    }

    /// `attachSongsToPlaylist` — `POST /library/user-playlist/:playlistId/attach`,
    /// body `{songIds: [String]}`.
    static func attachSongsToPlaylist(playlistId: String) -> Endpoint {
        .post("/library/user-playlist/\(playlistId)/attach")
    }

    /// `detachSongsFromPlaylist` — `POST /library/user-playlist/:playlistId/detach`,
    /// body `{songIds: [String]}`.
    static func detachSongsFromPlaylist(playlistId: String) -> Endpoint {
        .post("/library/user-playlist/\(playlistId)/detach")
    }

    /// `getSongsByUserPlaylist` — `/library/user-playlist/:playlistId/songs?page=`.
    /// `perPage` defaults server-side to 10, same precedent as
    /// `userPlaylists(page:)` above.
    static func userPlaylistSongs(playlistId: String, page: Int) -> Endpoint {
        .get("/library/user-playlist/\(playlistId)/songs?page=\(page)")
    }

    // MARK: Search (T40/T41) — `SEARCH_API.md` (`GET /api/search`) and its
    // real client, `SearchBloc._buildBody` (`lib/blocs/search/bloc.dart`).
    // `SEARCH_API.md`'s own params table omits `includeCompanyPlaylists`/
    // `excludeFollowed` entirely — both are grounded against `_buildBody`
    // itself, the more authoritative source, not that (incomplete) table.

    /// - Parameters:
    ///   - filter: `nil` for universal (all-tabs) search.
    ///   - musicPage/episodePage/creatorPage/playlistPage: always sent, all
    ///     four, same as `_buildBody` — the server only advances the section
    ///     matching `filterType`, but sending every cursor costs nothing and
    ///     matches the real client exactly.
    ///   - userPlaylistId: excludes songs already on that playlist — the
    ///     add-to-playlist flow's own param, unused by T40's plain search
    ///     but part of the same endpoint contract.
    static func search(
        query: String,
        filter: SearchFilter?,
        musicPage: Int,
        episodePage: Int,
        creatorPage: Int,
        playlistPage: Int,
        userPlaylistId: String? = nil
    ) -> Endpoint {
        var path = "/search?query=\(percentEncoded(query))"
        path += "&musicPage=\(musicPage)&episodePage=\(episodePage)"
        path += "&creatorPage=\(creatorPage)&playlistPage=\(playlistPage)"
        // Explicit opt-in the server requires before it will include company
        // playlists at all — see `SEARCH_API.md`'s "Opting in" section.
        // Unconditional, matching `_buildBody`'s own unconditional send.
        path += "&includeCompanyPlaylists=true"
        if let filter {
            path += "&filterType=\(filter.rawValue)"
            // `_buildBody`: `filter == creator && !excludeFollowedCreators`.
            // T40's screen is the general (unscoped) search page, where
            // `_excludeFollowedCreators` (`content_search_page.dart`) is
            // always false — so this app only ever sends the override on
            // the Artists tab, unconditionally within that tab.
            if filter == .creator {
                path += "&excludeFollowed=false"
            }
        }
        if let userPlaylistId {
            path += "&userPlaylistId=\(percentEncoded(userPlaylistId))"
        }
        return .get(path)
    }

    /// Same allowed-character policy as `AudioSourceResolver.proxyURL` — free
    /// text (this endpoint's `query`) can contain `&`/`=`/`+`/spaces, none of
    /// which are safe to paste directly into a hand-built query string.
    private static func percentEncoded(_ value: String) -> String {
        var allowedCharacters = CharacterSet.urlQueryAllowed
        allowedCharacters.remove(charactersIn: "&=+")
        return value.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? value
    }

    // MARK: Support / account deletion (T71) — `end_points.dart`'s
    // `getFaqsApi`/`sendFeedbackApi`/`deleteUserDataApi`, confirmed against
    // the real mounted routes (`dashboard.routes.js:289-290`,
    // `user.routes.js:24`) rather than Dart's own occasionally-stale verb
    // comments (see `logout`/`refreshToken` above for the same pattern).

    /// `getFaqsApi = "/support/faqs"` (`end_points.dart:325`), real route
    /// `dashboard.routes.js:290` → `getFAQs` (`support.controller.js:55`).
    /// Response: `{data: [{id, question, answer}]}`.
    static let faqs = Endpoint.get("/support/faqs")

    /// `sendFeedbackApi = "/support/feedback"` (`end_points.dart:326`), real
    /// route `dashboard.routes.js:289` → `createFeedback`
    /// (`support.controller.js:144`). The controller also accepts optional
    /// `email`/`image`, but `FeedbackPage._onSubmit` (`feedback.dart`) only
    /// ever sends `{title, description}` — matching the real Dart client's
    /// narrower request, not the controller's wider optional surface.
    static let sendFeedback = Endpoint.post("/support/feedback")

    /// `deleteUserDataApi = "/users/account/request/delete"`
    /// (`end_points.dart:97`) comments this `// DELETE`, but both the real
    /// call site (`AuthBloc.delete`, `bloc.dart:403`, via
    /// `DioApi.instance.getData`) and the actual mounted route
    /// (`user.routes.js:24`: `router.get('/account/request/delete', ...)`)
    /// agree it's really a GET — same stale-comment-vs-real-verb mismatch
    /// already flagged repeatedly in this file. `reason` travels as a query
    /// param (`requestDeleteUser`, `user.controller.js:~989`: `req.query`),
    /// matching Dart's own `getData(url, body: {...})` — that `body` becomes
    /// `queryParameters` for a GET (same idiom as `creatorSongs` above).
    /// Schedules deletion 7 days out and blacklists the access token
    /// server-side; it does not delete synchronously.
    static func deleteAccount(reason: String) -> Endpoint {
        .get("/users/account/request/delete?reason=\(percentEncoded(reason))")
    }

    // MARK: Notifications (T66) — `end_points.dart`'s `syncNotificationTopicsApi`/
    // `saveFcmTokenApi`, and `EndPoints.markVerseOfDayClicked`, confirmed
    // against the real mounted routes (`user.routes.js:17,21`,
    // `verseOfDay.routes.js:24`).

    /// `syncNotificationTopicsApi` (`end_points.dart:93`) — mirrors this
    /// device's FCM topic subscriptions onto the server, real call site
    /// `FirebaseMessagingService.reportSubscriptions` (`fcm_service.dart`).
    /// Body: `{fcmToken, deviceId?, deviceType?, deviceName?, topicKeys}` —
    /// `topicKeys` is the device's COMPLETE current subscription set, the
    /// server replaces rather than merges.
    static let syncNotificationTopics = Endpoint.post("/user/notification-topics/sync")

    /// `saveFcmTokenApi` (`end_points.dart:88`) — the simpler standalone
    /// token save, independent of `syncNotificationTopics` above. Body:
    /// `{fcmToken, deviceId}`, both required (400 if either is missing).
    static let saveFcmToken = Endpoint.post("/user/save/fcm-token")

    /// `EndPoints.markVerseOfDayClicked` (`end_points.dart:271`) —
    /// fire-and-forget click tracking for a verse-of-day push, real call
    /// site `FirebaseMessagingService.onNotificationOpen`/
    /// `openNotificationTarget` (`fcm_service.dart`).
    static func markVerseOfDayClicked(id: String) -> Endpoint {
        .get("/book/verse-of-day/mark-clicked/\(id)")
    }
}

/// `HOME_V2_API.md` §3: "anything else falls back to `all`" server-side —
/// there is no fourth case to add here for that reason.
enum HomeContentType: String, Sendable {
    case music, episode, all
}
