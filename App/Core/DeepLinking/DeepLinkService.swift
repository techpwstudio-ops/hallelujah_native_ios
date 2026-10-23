import Foundation

/// Native port of `DeepLinkService` (`lib/services/deep_link_service.dart`) —
/// the singleton that resolves both universal links (`applinks:` domains in
/// `Hallelujah.entitlements`) and the `gshallelujah://` custom scheme
/// (`Info.plist`) into an in-app destination.
///
/// `static let shared`, not `@Injected` on `HallelujahApp` itself: this
/// needs to exist before `AppNavigationCoordinator` does (a URL can arrive
/// during the splash/auth flow, before `AppShellView` has ever appeared),
/// and a plain struct property on `HallelujahApp` would resolve its
/// dependencies at an initialization-order point relative to
/// `AppComposition.installRuntime()` that can't be verified without a
/// compiler. A lazy `static let`'s first access is guaranteed to happen
/// after `HallelujahApp.init()` has already run, so this is unambiguously
/// safe instead. Mirrors Dart's own `DeepLinkService.instance` shape either
/// way.
///
/// SwiftUI's `.onOpenURL(perform:)` (wired in `HallelujahApp`) delivers
/// both custom-scheme and universal-link URLs, for both cold launch and a
/// running app, through this one callback — collapsing Dart's three-part
/// `captureInitialLink()` (cache) / `init()` (300ms-delayed consume) /
/// `listen()` (warm-start stream) dance into a single native mechanism.
/// What Dart's dance is still needed for — a link arriving before there's
/// anywhere to route it — is handled here by `pendingURL` instead: buffered
/// until `attach(coordinator:)` runs (`AppShellView.onAppear`), which mirrors
/// Dart's cache-then-consume shape but keyed off "the app shell is mounted"
/// rather than a fixed timer.
///
/// Scope cuts, both deliberate: Dart's `handle()` fires a
/// `FirebaseAnalytics.logEvent('appLinks', ...)` and surfaces failures via
/// `showSnackBarToast` / a `Loader`. Neither is wired here — analytics event
/// vocabulary is entirely T38's territory (`AppComposition`'s
/// `AnalyticsSyncEngine` is still a stub), and `ToastCenter`/`.toastOverlay()`
/// (T12) isn't applied anywhere near the real app root yet (only the
/// DesignSystem gallery uses it) — wiring either just for two edge-case
/// error paths here would be scope creep. Failures log via `AppLogger`
/// instead.
@MainActor
final class DeepLinkService {
    static let shared = DeepLinkService()

    @Injected private var httpClient: HTTPClient
    private let logger = AppLogger(category: .deepLinking)

    private weak var coordinator: AppNavigationCoordinator?
    private var pendingURL: URL?

    private init() {}

    /// Called from `AppShellView.onAppear` — the native proxy for Dart's
    /// `OurSession.instance.user != null` gate in `handle()`: the shell only
    /// ever mounts once `RootView` has resolved to `LaunchDestination.app`,
    /// which itself only happens for a signed-in session (T15).
    ///
    /// TODO(T21-24 audit finding): unlike Dart, which re-checks
    /// `OurSession.instance.user != null` on *every* dispatch (cache-flush
    /// and live-stream alike), `pendingURL` here is flushed unconditionally
    /// with no re-verification and no expiry. `AuthenticationView` (T21) now
    /// gives `RootView` a real sign-in to sign OUT of, but sign-out itself
    /// isn't wired until T26 — so a link buffered while signed out still
    /// can't yet fire after a later, possibly different, sign-in within one
    /// process lifetime. Revisit once T26 lands sign-out, so a stale buffered
    /// link can't silently fire post-switch.
    func attach(coordinator: AppNavigationCoordinator) {
        self.coordinator = coordinator
        guard let url = pendingURL else { return }
        pendingURL = nil
        dispatch(url, coordinator: coordinator)
    }

    /// Called from `AppShellView.onDisappear`. Nothing currently tears the
    /// shell down mid-session (sign-out isn't wired until T20-24), but this
    /// costs nothing now and is correct the day something does.
    func detach() {
        coordinator = nil
    }

    /// `HallelujahApp`'s `.onOpenURL` calls this for every delivery — cold
    /// launch and warm start alike.
    func receive(_ url: URL) {
        ReferralAttributionStore.shared.record(url)
        guard let coordinator else {
            pendingURL = url
            return
        }
        dispatch(url, coordinator: coordinator)
    }

    /// An ad's `deeplink` action: one of our own share links, handled exactly
    /// as a tapped share link — minus the referral attribution `receive`
    /// records, which an in-app ad tap isn't.
    func openAdLink(_ url: URL, coordinator: AppNavigationCoordinator) {
        dispatch(url, coordinator: coordinator)
    }

    private func dispatch(_ url: URL, coordinator: AppNavigationCoordinator) {
        Task { await handle(url, coordinator: coordinator) }
    }

    /// `handle(Uri)` (`deep_link_service.dart`). The `uri.pathSegments.length
    /// == 2` gate is generic to any 2-segment path regardless of scheme —
    /// nothing in the Dart client ever constructs these links itself (that's
    /// entirely server-controlled), so this ports only that one invariant
    /// rather than inventing a concrete path shape.
    private func handle(_ url: URL, coordinator: AppNavigationCoordinator) async {
        logger.info("deep link received: \(url)")

        let segments = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard segments.count == 2 else { return }
        let code = segments[1]

        // `Loader.instance.show()` ... `finally { Loader.instance.hide() }`.
        GlobalLoader.shared.show()
        defer { GlobalLoader.shared.hide() }
        do {
            let response = try await httpClient.send(.validateDeepLink(code: code))
            guard response.statusCode == 200 || response.statusCode == 201 else {
                // 404 gets its own toast; every other status is dropped
                // silently on purpose, same as Dart's "any other status is
                // ignored" comment — resolving an incoming link is a passive
                // background flow.
                logger.warning("deep link \(code) validate returned \(response.statusCode)")
                if response.statusCode == 404 {
                    ToastCenter.shared.show("This link is no longer available.")
                }
                return
            }
            guard let validation = DeepLinkValidationResponse(data: response.data) else {
                logger.warning("deep link \(code) validate returned an unrecognised payload shape")
                ToastCenter.shared.show("Unable to open this link. Please try again.")
                return
            }
            openShareable(shareableType: validation.deepLink.shareableType, item: validation.item, coordinator: coordinator)
        } catch {
            logger.warning("deep link \(code) validate failed: \(error)")
        }
    }

    /// `openShareable` (`deep_link_service.dart`) — also `ad_action.dart`'s
    /// entry point for an in-app-destination ad CTA (an ad pointing at a
    /// creator/playlist/song opens exactly like a shared link to that
    /// content). `internal`, not `private`, for M11 to call once ads exist;
    /// unused by anything else until then.
    ///
    /// No Realm-equivalent caching here for any branch, unlike Dart: there's
    /// no local persistence layer for Song/Creator/Playlist/VerseOfDay yet
    /// (M4+/M7/M9 territory) to cache into — most branches below push a bare
    /// id and let the destination screen re-fetch once it exists. `.playlist`
    /// /`.companyPlaylist` are the exception (T43): `PlaylistDetailViewModel`
    /// never re-fetches metadata, only songs, so those two branches pull
    /// title/image/songsCount straight off `item`'s raw, unselected Prisma
    /// row and carry the header along with the route instead.
    func openShareable(shareableType rawType: String?, item: [String: Any], coordinator: AppNavigationCoordinator) {
        guard let rawType, let type = ShareableType(rawValue: rawType) else { return }
        let id = Self.stringID(from: item["id"])

        switch type {
        case .app:
            // No branch in Dart's own if/else-if chain either — the app is
            // already open, so there's nothing further to do.
            break

        case .song:
            // Dart doesn't navigate for this case at all — it caches the
            // song and fires `PlaySongEvent(playerType: invite)`, starting
            // playback directly; the mini player then appears wherever the
            // user already is.
            guard let id else { return }
            Task { await playSong(id: id) }

        case .creator:
            guard let id else { return }
            coordinator.push(.creatorSongs(creatorID: id, userPlaylistID: nil))

        case .userPlaylist:
            guard let id else { return }
            coordinator.push(.userPlaylistSongs(playlistID: id))

        case .playlist:
            // `validateDeepLink`'s `playlist` branch is a bare, unselected
            // `prisma.playlist.findFirst` — no `include: { creator: true }`
            // — so `item` carries `creatorId` but never a creator name.
            // `PlaylistDetailViewModel` never re-fetches metadata (only
            // songs), so the header has to travel with the route; an absent
            // `creatorName` just means `PlaylistDetailView` shows no
            // creator line for a deep-linked album/season, same as any
            // other field this raw row happens not to carry.
            guard let id else { return }
            coordinator.push(.playlistDetail(
                playlistID: id,
                title: item["title"] as? String ?? "",
                image: item["image"] as? String,
                imageVariants: item["imageVariants"] as? String,
                songsCount: item["songsCount"] as? Int,
                isCompanyOwned: false,
                creatorID: Self.stringID(from: item["creatorId"]),
                creatorName: nil
            ))

        case .companyPlaylist:
            guard let id else { return }
            coordinator.push(.playlistDetail(
                playlistID: id,
                title: item["title"] as? String ?? "",
                image: item["image"] as? String,
                imageVariants: item["imageVariants"] as? String,
                songsCount: item["songsCount"] as? Int,
                isCompanyOwned: true,
                creatorID: nil,
                creatorName: nil
            ))

        case .verseOfDay, .bibleVerse:
            // `ReadService.openVerse` flips Bible-reader bloc state to
            // scroll to a specific verse rather than pushing a route — it
            // has no native equivalent yet (no reader state exists before
            // M9). `NavigationService.offAll(DashBoardContainer.routeName)`
            // is the part that does have one: reset to the Read tab's root.
            coordinator.resetToRoot(selecting: .read)
            // Cache the shared row (only a full row, not a push's bare ids),
            // then scroll the reader to the verse.
            if type == .verseOfDay, item["verseText"] != nil {
                VerseOfDayIngest.ingest(item: item, makeCurrent: false)
            }
            ReaderVerseOpener.open(from: item)
        }
    }

    /// A shared / pushed song starts playing on its own, as a one-song queue
    /// attributed to `PlayerType.invite`. The full song is fetched rather than
    /// built from the link's lightweight projection (`GET /song/:id` is the
    /// `openNotificationTarget` path in Dart and carries every field the
    /// player needs); a failed fetch is the "no longer available" toast.
    @discardableResult
    func playSong(id: String) async -> Bool {
        let container = DependencyContainer.current
        guard let repository = container.resolveIfRegistered((any SongRepository).self),
              let queue = container.resolveIfRegistered(QueueController.self) else { return false }
        GlobalLoader.shared.show()
        let fetched: Song
        do {
            fetched = try await repository.fetchSong(id: id)
            GlobalLoader.shared.hide()
        } catch {
            GlobalLoader.shared.hide()
            logger.warning("deep link: song \(id) could not be opened: \(error)")
            ToastCenter.shared.show("This song is no longer available.")
            return false
        }
        await queue.play(
            songs: [fetched],
            startIndex: 0,
            source: QueueAttribution(playerType: .invite, id: nil, title: "")
        )
        return true
    }

    /// `company_playlist.dart`'s `getCompanyPlaylistFromJson` is the one
    /// sibling model that `.toString()`s its id defensively; the rest
    /// (`song.dart`, `creator.dart`, `user_playlist.dart`, `playlist.dart`)
    /// all assume a String outright. Matching the defensive one costs
    /// nothing and covers every case.
    private static func stringID(from value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? any CustomStringConvertible { return value.description }
        return nil
    }

    // MARK: - Outbound share links (T68)

    /// Mirrors `RemoteBibleRepository.shareVerse(id:)`'s two failure cases —
    /// no repository owns a bare song/creator/playlist "share" concern
    /// natively (checked `PlaylistRepository`/`CreatorRepository`/
    /// `UserPlaylistRepository` — none of them do), so this lives here
    /// instead, matching Dart's own `DeepLinkService` owning both inbound
    /// `handle()` and outbound `create*()`.
    enum ShareLinkError: Error {
        case unexpectedStatus(Int)
        case invalidShareURL
    }

    /// `create(songId)` (`deep_link_service.dart`).
    func songShareLink(id: String) async throws -> URL {
        try await fetchShareLink(.songShare(id: id))
    }

    /// `createCreatorLink(creatorId)`.
    func creatorShareLink(id: String) async throws -> URL {
        try await fetchShareLink(.creatorShare(id: id))
    }

    /// `sharePlaylist(UserPlaylist)`. Capability only — `UserPlaylistDetailView`
    /// deliberately has no Share entry point yet (T45's own scope cut,
    /// "Follow/Share are non-owner Dart affordances this rewrite defers"),
    /// so nothing calls this today. Kept here so a future pass revisiting
    /// that cut only needs to wire a button, not mint a new endpoint.
    func userPlaylistShareLink(id: String) async throws -> URL {
        try await fetchShareLink(.userPlaylistShare(id: id))
    }

    /// `createCompanyPlaylistLink(playlistId)`.
    func companyPlaylistShareLink(id: String) async throws -> URL {
        try await fetchShareLink(.companyPlaylistShare(id: id))
    }

    /// `createVerseOfDayLink(verseOfDayId)`. Unused: T56 landed with its own
    /// independent minting path (`VerseOfDayCardViewModel.refresh()` calls
    /// `VerseOfDayRepository.shareURL(id:)` directly, wired to a plain
    /// `ShareLink(item:)` in `VerseOfDayCardView`'s action bar) rather than
    /// this method — both ultimately hit the same `verseOfDayShare(id:)`
    /// endpoint, so there's no behavioral gap, just a second unused path.
    /// Left in place rather than deleted: harmless, and matches this file's
    /// other four sibling methods.
    func verseOfDayShareLink(id: String) async throws -> URL {
        try await fetchShareLink(.verseOfDayShare(id: id))
    }

    /// `createAiMessageLink(messageId)` — the link an AI answer is shared with.
    func aiMessageShareLink(id: String) async throws -> URL {
        try await fetchShareLink(.aiMessageShare(id: id))
    }

    private func fetchShareLink(_ endpoint: Endpoint) async throws -> URL {
        try await shareLink(endpoint).url
    }

    /// The minted link plus the card image the server returns with it
    /// (`DeepLink.image` / `imageVariants`), for the share card.
    func shareLink(_ endpoint: Endpoint) async throws -> MintedShareLink {
        let response = try await httpClient.send(endpoint)
        guard response.statusCode == 200 else {
            throw ShareLinkError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(ShareLinkResponseDTO.self, from: response.data)
        guard let url = URL(string: decoded.data.link) else {
            throw ShareLinkError.invalidShareURL
        }
        return MintedShareLink(url: url, image: decoded.data.image, imageVariants: decoded.data.imageVariants)
    }
}

struct MintedShareLink: Sendable {
    let url: URL
    let image: String?
    let imageVariants: String?
}

/// `{data: {link}}` — same envelope shape as `RemoteBibleRepository`'s own
/// `ShareVerseResponseDTO`/`ShareVerseDataDTO` (`BibleSyncDTOs.swift`), kept
/// as a separate, locally-named pair rather than reusing that Bible-specific
/// DTO for song/creator/playlist responses too.
private struct ShareLinkResponseDTO: Decodable {
    let data: ShareLinkDataDTO
}

private struct ShareLinkDataDTO: Decodable {
    let link: String
    let image: String?
    let imageVariants: String?
}

/// The `{deepLink, item}` envelope `handle()` expects from
/// `validateDeepLinkApi` — parsed with `JSONSerialization` rather than
/// `Codable` for `item`, since its shape varies per `ShareableType` and
/// nothing decodes it into a model yet (see `openShareable`'s note on
/// caching).
private struct DeepLinkValidationResponse {
    let deepLink: DeepLink
    let item: [String: Any]

    init?(data: Data) {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let deepLinkJSON = root["deepLink"] as? [String: Any],
            let item = root["item"] as? [String: Any],
            let deepLinkData = try? JSONSerialization.data(withJSONObject: deepLinkJSON),
            let deepLink = try? JSONDecoder().decode(DeepLink.self, from: deepLinkData)
        else { return nil }

        self.deepLink = deepLink
        self.item = item
    }
}
