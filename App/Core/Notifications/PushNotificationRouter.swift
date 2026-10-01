import Foundation

/// Native port of the tap-routing half of `FirebaseMessagingService`
/// (`lib/services/fcm_service.dart`)'s `onNotificationOpen`/
/// `openNotificationTarget` — resolves a tapped push notification's payload
/// into an in-app destination. Delivery-side handling (`PushNotificationService`)
/// is kept separate, the same way `DeepLinkService.receive` is kept apart
/// from whatever hands it a URL.
///
/// `static let shared`, not `@Injected`, for the same reason
/// `DeepLinkService.shared` is (see that type's own doc comment): a tap can
/// arrive before `AppNavigationCoordinator` exists (cold-start launch racing
/// the splash/auth flow), so this needs a stable identity from before that
/// point, and a lazy `static let`'s first access is guaranteed to happen
/// after `GHallelujahApp.init()` already has. Structurally mirrors
/// `DeepLinkService` closely: a buffered pending payload flushed by
/// `attach(coordinator:)` instead of dropping a tap that races the shell
/// mounting, same shape as that type's own `pendingURL`.
///
/// Route resolution reuses `DeepLinkService.shared.openShareable` wherever
/// its `item` shape is satisfiable without a fetch, instead of re-deriving
/// the destination switch a second time — see that method's own doc comment
/// for why it's `internal`, not `private`.
@MainActor
final class PushNotificationRouter {
    static let shared = PushNotificationRouter()

    @Injected private var httpClient: HTTPClient
    private let logger = AppLogger(category: .notifications)

    private weak var coordinator: AppNavigationCoordinator?
    private var pendingUserInfo: [AnyHashable: Any]?

    private init() {}

    /// Called from `AppShellView.onAppear`, same lifecycle point as
    /// `DeepLinkService.attach(coordinator:)`.
    func attach(coordinator: AppNavigationCoordinator) {
        self.coordinator = coordinator
        guard let userInfo = pendingUserInfo else { return }
        pendingUserInfo = nil
        dispatch(userInfo, coordinator: coordinator)
    }

    /// Called from `AppShellView.onDisappear`, mirrors `DeepLinkService.detach()`.
    func detach() {
        coordinator = nil
    }

    /// `PushNotificationService.handleNotificationResponse` calls this for
    /// every notification tap — cold launch and warm/background alike.
    func handle(userInfo: [AnyHashable: Any]) {
        guard let coordinator else {
            pendingUserInfo = userInfo
            return
        }
        dispatch(userInfo, coordinator: coordinator)
    }

    private func dispatch(_ userInfo: [AnyHashable: Any], coordinator: AppNavigationCoordinator) {
        Task { await route(userInfo, coordinator: coordinator) }
    }

    /// `onNotificationOpen`'s `topic == 'verse_of_day'` branch, checked
    /// first, then `openNotificationTarget`'s `shareableType`/`shareableId`
    /// switch (`fcm_service.dart`) — two separate, non-overlapping keyings
    /// the server uses for the daily-verse campaign vs. an admin-composed
    /// push.
    private func route(_ userInfo: [AnyHashable: Any], coordinator: AppNavigationCoordinator) async {
        if (userInfo["topic"] as? String) == "verse_of_day" {
            let verseOfDayID = (userInfo["verseOfDayId"] as? String) ?? ""
            // Fire-and-forget, matching Dart's own un-awaited `.then` here —
            // `openShareable`'s `.verseOfDay` branch (below) only resets to
            // the Read tab, so navigation has nothing to wait on this for.
            Task { await markVerseOfDayClicked(id: verseOfDayID) }
            DeepLinkService.shared.openShareable(
                shareableType: ShareableType.verseOfDay.rawValue,
                item: ["id": verseOfDayID],
                coordinator: coordinator
            )
            return
        }

        // Absent is the empty string, not the literal "null" — FCM data
        // values are always strings server-side, same as `onNotificationOpen`'s
        // own comment on this exact pair. `app` is a real destination
        // meaning "just open the app", so it's a deliberate no-op rather
        // than an unknown type.
        let shareableType = (userInfo["shareableType"] as? String) ?? ""
        let shareableId = (userInfo["shareableId"] as? String) ?? ""
        guard
            !shareableType.isEmpty,
            shareableType != ShareableType.app.rawValue,
            !shareableId.isEmpty
        else { return }

        switch shareableType {
        case ShareableType.song.rawValue, ShareableType.creator.rawValue, ShareableType.userPlaylist.rawValue:
            // All three branches of `DeepLinkService.openShareable` only
            // ever read `item["id"]`.
            DeepLinkService.shared.openShareable(
                shareableType: shareableType,
                item: ["id": shareableId],
                coordinator: coordinator
            )

        case ShareableType.playlist.rawValue:
            await openPrefetchedPlaylist(
                id: shareableId,
                endpoint: .playlistSongs(id: shareableId, page: 1),
                shareableType: shareableType,
                coordinator: coordinator
            )

        case ShareableType.companyPlaylist.rawValue:
            await openPrefetchedPlaylist(
                id: shareableId,
                endpoint: .companyPlaylistSongs(id: shareableId, page: 1),
                shareableType: shareableType,
                coordinator: coordinator
            )

        case ShareableType.verseOfDay.rawValue:
            // Same fire-and-forget shape as the `topic` branch above — its
            // `openShareable` branch ignores `item` entirely (see that
            // method's own doc comment).
            Task { await markVerseOfDayClicked(id: shareableId) }
            DeepLinkService.shared.openShareable(
                shareableType: shareableType,
                item: ["id": shareableId],
                coordinator: coordinator
            )

        default:
            // Logged rather than silently dropped — an unhandled destination
            // looks exactly like a broken notification from the user's side,
            // same reasoning `openNotificationTarget`'s own trailing `print`
            // documents.
            logger.info("push tap: no handler for shareableType \"\(shareableType)\"")
        }
    }

    /// Shared by `.playlist`/`.companyPlaylist`: both endpoints wrap their
    /// row under the same `data.playlist` key despite differing `meta`
    /// shapes (`getPlaylistSongs` vs `getCompanyPlaylistSongs`,
    /// `playlist.controller.js`/`companyPlaylist.controller.js`), so one
    /// extraction — mirroring `DeepLinkService.handle`'s own
    /// `JSONSerialization`-based parsing style rather than adding a Codable
    /// model for a dict `openShareable` already accepts raw — covers both.
    private func openPrefetchedPlaylist(
        id: String,
        endpoint: Endpoint,
        shareableType: String,
        coordinator: AppNavigationCoordinator
    ) async {
        do {
            let response = try await httpClient.send(endpoint)
            guard
                response.statusCode == 200,
                let root = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
                let data = root["data"] as? [String: Any],
                let playlist = data["playlist"] as? [String: Any]
            else {
                logger.warning("push tap: \(shareableType) \(id) fetch returned an unusable payload")
                return
            }
            DeepLinkService.shared.openShareable(shareableType: shareableType, item: playlist, coordinator: coordinator)
        } catch {
            logger.warning("push tap: \(shareableType) \(id) fetch failed: \(error)")
        }
    }

    /// `EndPoints.markVerseOfDayClicked` (`fcm_service.dart`'s
    /// `onNotificationOpen`/`openNotificationTarget`) — fire-and-forget by
    /// design, same posture `PushNotificationTokenRegistrar`'s own doc
    /// comment documents for its sibling calls: a failed click-mark must
    /// never block navigation or surface to the user.
    private func markVerseOfDayClicked(id: String) async {
        do {
            _ = try await httpClient.send(.markVerseOfDayClicked(id: id))
        } catch {
            logger.warning("markVerseOfDayClicked(\(id)) failed: \(error)")
        }
    }
}
