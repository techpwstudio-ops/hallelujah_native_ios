import Foundation

/// Typed stand-in for the `Map<String, dynamic>` extras Dart's `GoRoute`
/// builders unpack (`lib/routes/app_router.dart`) — one case per pushable
/// destination reachable from inside a tab's stack. Two groups of Dart
/// routes are deliberately **not** here, because they're not `.to()`-style
/// pushes in Dart either — every `NavigationService.pushModal` call site
/// was grepped to confirm exactly what it targets:
///
/// - Tab roots (`Home`, `SearchPage`, `AiPage`, `LibraryPage`, `ReadPage`) —
///   those are `AppTab`, not pushes.
/// - `AiVoiceOverlayPage`/`AiAudioConversationPage` (hands-free voice, from
///   `ai_chat_page.dart`/`ai_page.dart`) and `AudioPlayerScreen` (from the
///   mini-player dock and the ad-break banner) — the only three
///   destinations `pushModal` actually targets. Modeled as
///   `FullScreenDestination` since they're a full-screen-cover
///   presentation, not a stack push. `AiChatPage` itself is a regular
///   `.to()` push (see `ai_verse_insight_dialog.dart`), so it's `.aiChat`
///   below, not a `FullScreenDestination`.
/// - `QueuePage`/`SongLyricsPage` additionally ride along inside the
///   player's own presentation as `PlayerRoute` — together with
///   `AudioPlayerScreen` they're Dart's `playerOwnedRoutes`
///   (`lib/routes/routes.dart`), popped as a unit by
///   `NavigationService.popPlayerScreens()`; see
///   `AppNavigationCoordinator.popPlayerScreens()` for why dismissing one
///   `FullScreenDestination` is a cleaner native shape than porting Dart's
///   `popUntil` scan.
///
/// Payloads mirror what Dart actually threads through `extra`: almost every
/// route there takes primitives/Strings/enums, not model objects — even
/// other playlist- and creator-scoped routes (`UserPlaylistSongs`,
/// `CreatorSongsPage`, `CompanyPlaylistSongsPage`) pass an id string rather
/// than a full object. `playlistSongs` and `genreSongs` are the two
/// exceptions (`PlaylistSongPage` takes a `CreatorPlaylist`, `GenreSongs` a
/// `Genre`) — both originally used an id-only shape here until a domain
/// model existed worth widening the payload for. `genreSongs` (T42) is now
/// that widened case: `Genre` exists, the backend has no single-genre
/// detail endpoint to re-fetch by id from (`genre.controller.js` exports
/// only `getGenres`/`getGenreSongs`), and `CategoryUI.onTap`
/// (`category_ui.dart:22-26`) passes the whole already-loaded `Genre` object
/// through `NavigationService.to`, exactly the shape this now mirrors —
/// exploded into primitive fields rather than an embedded `Genre` struct,
/// matching every other multi-field case here (`favouriteSongs`,
/// `creatorGrid`, `recentSongs`). `playlistSongs`/`companyPlaylistSongs`
/// (T43) are now unified into `playlistDetail`, widened the same way for
/// the same reason: `Playlist` now exists and backs both
/// `PlaylistDetailView`, and Library's merged list (`LibraryEntryRow`)
/// already has the full row loaded when the user taps it, same as
/// `CategoryUI.onTap` above. `userPlaylistSongs` stays id-only: no
/// `UserPlaylist`-equivalent domain model backs it yet (T45).
enum AppRoute: Hashable, Sendable {
    // MARK: Settings / profile / account

    case settings
    case profile
    case notificationSettings
    case subscriptionPlans
    case manageFamilyMembers
    case deleteAccount
    case contentLanguage(label: String, canPop: Bool)

    // MARK: Help / support

    case helpSupportDashboard
    case faqs
    case feedback

    // MARK: Search-adjacent

    case genreSearch
    case episodes
    /// `ContentSearchPage` (`lib/routes/app_router.dart`) — Dart also
    /// forwards `customPlaylist`/`searchUiItemType` as untyped `dynamic`
    /// fields with no fixed shape even there; dropped here until the
    /// content picker itself gets built and gives them a real type.
    /// `checkedContent` is kept, unlike those two: it's stably typed
    /// (`List<String>`, same shape as `tags`) and seeds `SelectContentBloc`
    /// so the picker opens with already-selected songs pre-checked — a real
    /// call site, `lib/helpers/add_to_custom_playlist.dart`, passes the
    /// playlist's existing song ids through it.
    case contentSearch(userPlaylistID: String?, tags: [String], checkedContent: [String], isSelect: Bool)

    // MARK: AI

    case aiHistory
    case aiChat(conversationID: String?, initialMessage: String?)

    // MARK: Library / playlists / creators

    case downloads(type: String)
    /// T47 — pushed from `DownloadsView`'s toolbar.
    case storageSettings
    case createPlaylist(userPlaylistID: String?, songType: String?, songID: String?)
    case creatorGrid(title: String, songType: String)
    case creatorSongs(creatorID: String?, userPlaylistID: String?)
    case userPlaylistSongs(playlistID: String?)
    /// Replaces the old id-only `companyPlaylistSongs`/`playlistSongs` pair
    /// (T43) — see this file's top doc comment. `isCompanyOwned` selects
    /// `PlaylistOwner.company` vs. `.creator(id:name:)` when rebuilding a
    /// `Playlist` from these exploded fields at the destination.
    case playlistDetail(
        playlistID: String,
        title: String,
        image: String?,
        imageVariants: String?,
        songsCount: Int?,
        isCompanyOwned: Bool,
        creatorID: String?,
        creatorName: String?
    )
    case favouriteSongs(type: String?, label: String, asset: String)
    case favouriteArtists(songType: String)
    case genreSongs(genreID: String?, genreName: String?, genreImage: String?, genreImageVariants: String?)

    // MARK: Song lists

    case recentSongs(
        image: String?,
        viewType: String?,
        label: String,
        songIDs: [String?],
        imageURL: String?,
        imageVariants: String?
    )
    case seeAllSongs(
        type: String?,
        viewType: String?,
        image: String?,
        imageVariants: String?,
        imageURL: String?,
        uniqueIDWithType: String?,
        label: String,
        songIDs: [String?],
        homeListUnitModelDataID: String?
    )
    case seeAllArtists(type: String?, title: String, homeListUnitModelDataID: String?, viewType: String?)

    // MARK: Misc

    case bibleVerseShare(verseReference: String, verseText: String, deepLinkURL: String)
    case cropCompressImage(path: String, aspectRatio: Double)
}

// MARK: - Tab bar / mini-player visibility (T17)

extension AppRoute {
    /// `canShowBottomNavBar`'s `hiddenRoutes` set (`lib/routes/routes.dart`),
    /// mapped onto this enum's cases. Several entries in that Dart set have
    /// no case here at all — `AuthenticationPage`/`AccountSetupPage`/
    /// `OtpScreen`/`EmailOtpScreen`/`FlashScreen`/`LaunchApp` aren't reachable
    /// from inside the shell (pre-sign-in or splash), and
    /// `AiVoiceOverlayPage`/`AiAudioConversationPage` are `FullScreenDestination`
    /// cases that already cover the whole screen, hiding this dock for free.
    var hidesTabBar: Bool {
        switch self {
        case .cropCompressImage, .contentSearch, .genreSearch, .subscriptionPlans,
             .manageFamilyMembers, .helpSupportDashboard, .profile, .notificationSettings,
             .createPlaylist, .faqs, .deleteAccount, .feedback, .aiChat, .bibleVerseShare:
            true
        case .settings, .contentLanguage, .episodes, .aiHistory, .downloads, .storageSettings,
             .creatorGrid, .creatorSongs, .userPlaylistSongs, .playlistDetail,
             .favouriteSongs, .favouriteArtists, .genreSongs,
             .recentSongs, .seeAllSongs, .seeAllArtists:
            false
        }
    }

    /// `canShowMusicPlayerBottom`'s `hiddenRoutes` set — two cases wider than
    /// `hidesTabBar`'s: `.contentLanguage` and `.creatorGrid` hide only the
    /// mini player in Dart, not the tab bar (confirmed by diffing both
    /// functions' literal sets against each other line by line). `.settings`
    /// is in neither set, hidden from nothing.
    var hidesMiniPlayer: Bool {
        switch self {
        case .cropCompressImage, .contentSearch, .genreSearch, .subscriptionPlans,
             .manageFamilyMembers, .helpSupportDashboard, .profile, .notificationSettings,
             .createPlaylist, .faqs, .deleteAccount, .feedback, .aiChat, .bibleVerseShare,
             .contentLanguage, .creatorGrid:
            true
        case .settings, .episodes, .aiHistory, .downloads, .storageSettings, .creatorSongs,
             .userPlaylistSongs, .playlistDetail, .favouriteSongs,
             .favouriteArtists, .genreSongs, .recentSongs, .seeAllSongs, .seeAllArtists:
            false
        }
    }
}
