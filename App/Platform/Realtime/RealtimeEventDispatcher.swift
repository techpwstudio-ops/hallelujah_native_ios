import Foundation

/// Ports `RealtimeEventHandler.dispatch`/its 9 named handlers
/// (`lib/services/realtime_event_handler.dart`) — transport-agnostic in Dart
/// (both FCM and WebSocket delegate into it) but T67 only wires the socket
/// side; a push-notification-data equivalent is T22/T66's concern if it ever
/// needs the same routing.
///
/// Dart's generic wildcard-suffix matching (`key.endsWith('*')`) is NOT
/// ported: none of the 9 real handler keys registered below are wildcards,
/// so that branch is dead code in the Dart source today too — porting it
/// would be speculative generality with nothing exercising it.
///
/// Event names are the backend's own `SocketEvents` constants
/// (`src/socket.io/events.js`), spelled out literally here (not a shared
/// enum) since nothing else in this app currently needs them.
@MainActor
final class RealtimeEventDispatcher {
    private let currentUserStore: CurrentUserStore
    private let eventBus: RealtimeEventBus
    private let notificationScheduler: LocalNotificationScheduler
    private let logger = AppLogger(category: .realtime)

    init(
        currentUserStore: CurrentUserStore,
        eventBus: RealtimeEventBus,
        notificationScheduler: LocalNotificationScheduler = LocalNotificationScheduler()
    ) {
        self.currentUserStore = currentUserStore
        self.eventBus = eventBus
        self.notificationScheduler = notificationScheduler
    }

    /// Called from `RealtimeConnectionManager`'s `onAny` handler with the raw
    /// socket.io event name and its single JSON argument (the whole
    /// `{event, data, ...}` envelope — see `RealtimeEnvelope`'s doc comment
    /// for why the server sends it that shape).
    func dispatch(name: String, items: [Any]?) {
        guard let envelope = RealtimeEnvelopeDecoding.envelope(from: items) else {
            logger.warning("realtime event '\(name)' — payload did not decode")
            return
        }

        switch name {
        case "users.playlist.updated":
            handlePlaylistUpdated(envelope)
        case "users.user.updated":
            handleUserUpdated(envelope)
        case "verseOfDay.update":
            handleVerseOfDayUpdated(envelope)
            eventBus.notifyVerseOfDayUpdated()
        case "verseOfDay.comment.like":
            handleVerseOfDayCommentLiked(envelope)
            eventBus.notifyVerseOfDayCommentLiked()
        case "verseOfDay.comment.added":
            handleVerseOfDayCommentAdded(envelope)
            eventBus.notifyVerseOfDayCommentAdded()
        case "premium.member.invite":
            handlePremiumInvite(envelope)
        case "premium.invite.update":
            handlePremiumInviteUpdated(envelope)
        case "premium.update":
            eventBus.notifyPremiumUpdated()
            refreshUserDetails()
        case "songs.public":
            handleSongPublished(envelope)
        default:
            logger.debug("no handler for realtime event: \(name)")
        }
    }

    /// `users.playlist.updated` only ever patches `image`/`imageVariants` on
    /// an existing local row in Dart (`realm.find<UserPlaylist>(playlistId)`,
    /// skipped entirely if not cached). There's no local playlist cache to
    /// patch the same way here (`LibraryViewModel` has no byId store — see
    /// this file's own top-level doc comment), so this only publishes the id
    /// on `RealtimeEventBus`; a library/playlist-detail view decides whether
    /// it cares enough to `refresh()`.
    private func handlePlaylistUpdated(_ envelope: RealtimeEnvelope) {
        guard let data = envelope.data,
              let payloadData = try? JSONEncoder().encode(data),
              let playlist = try? JSONDecoder().decode(PlaylistUpdatedPayload.self, from: payloadData) else {
            return
        }
        eventBus.notifyPlaylistUpdated(id: playlist.id)
    }

    /// `users.user.updated` — Dart: `OurSession.instance.updateUserModel({'user':
    /// event['data']})`, i.e. the envelope's `data` IS the fresh user object.
    /// `User` decodes the same wire shape `/users/me` returns (see `User`'s
    /// own `init(from:)`), so it decodes directly here too — no separate DTO.
    private func handleUserUpdated(_ envelope: RealtimeEnvelope) {
        guard let data = envelope.data,
              let payloadData = try? JSONEncoder().encode(data),
              let user = try? JSONDecoder().decode(User.self, from: payloadData) else {
            return
        }
        Task { await currentUserStore.setUser(user) }
    }

    /// The event's `data` as JSON bytes. Dart: `if (data is String) data = jsonDecode(data)`
    /// — the server sometimes sends the payload as a JSON string.
    private func payloadData(_ envelope: RealtimeEnvelope) -> Data? {
        guard let data = envelope.data else { return nil }
        if case .string(let text) = data { return Data(text.utf8) }
        return try? JSONEncoder().encode(data)
    }

    /// `verseOfDay.update` (`_onVerseOfDayUpdated`): `{id, likes, comments}`
    /// patches the cached verse, which the Home card observes.
    private func handleVerseOfDayUpdated(_ envelope: RealtimeEnvelope) {
        guard let payload = payloadData(envelope),
              let counts = try? JSONDecoder().decode(VerseOfDayCountsPayload.self, from: payload) else { return }
        VerseOfDayIngest.applyLiveCounts(id: counts.id, likes: counts.likes, comments: counts.comments)
    }

    /// `verseOfDay.comment.like` (`UpdateVerseOfDayCommentLikeEvent`).
    private func handleVerseOfDayCommentLiked(_ envelope: RealtimeEnvelope) {
        guard let payload = payloadData(envelope),
              let like = try? JSONDecoder().decode(VerseOfDayCommentLikePayload.self, from: payload) else { return }
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .verseOfDayCommentLikesChanged,
                object: nil,
                userInfo: ["commentId": like.commentId, "likes": like.likes, "verseOfDayId": like.verseOfDayId]
            )
        }
    }

    /// `verseOfDay.comment.added` (`InsertVerseOfDayCommentEvent`): the payload
    /// is a comment row, same shape as the comments endpoint.
    private func handleVerseOfDayCommentAdded(_ envelope: RealtimeEnvelope) {
        guard let payload = payloadData(envelope),
              let dto = try? JSONDecoder().decode(VerseOfDayCommentDTO.self, from: payload) else { return }
        let comment = dto.toDomain()
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .verseOfDayCommentAdded,
                object: nil,
                userInfo: ["comment": comment]
            )
        }
    }

    /// `data` as a plain dictionary (for the small, flat premium payloads).
    private func payloadObject(_ envelope: RealtimeEnvelope) -> [String: Any]? {
        guard let payload = payloadData(envelope) else { return nil }
        return (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any]
    }

    /// `premium.member.invite` (`_onPremiumInviteReceived`):
    /// `showInviteReceivedSheet(inviteId, inviterName, planName)` — foreground
    /// only in Dart (needs a UI context), which `AppInfrastructureHost`
    /// reproduces by presenting from the bus.
    private func handlePremiumInvite(_ envelope: RealtimeEnvelope) {
        guard let data = payloadObject(envelope), let invite = InitInviteInfo(realtimeData: data) else {
            logger.warning("premium.member.invite — payload had no inviteId")
            return
        }
        eventBus.notifyPremiumInviteReceived(invite)
    }

    /// `premium.invite.update` (`_onPremiumInviteStatusUpdated`).
    private func handlePremiumInviteUpdated(_ envelope: RealtimeEnvelope) {
        guard let data = payloadObject(envelope),
              let inviteId = data["inviteId"] as? String,
              let status = data["status"] as? String else { return }
        eventBus.notifyPremiumInviteStatusUpdated(PremiumInviteStatusUpdate(inviteId: inviteId, status: status))
    }

    /// `premium.update` (`_onPremiumUpdated`): `OurSession.fetchUserDetails()`
    /// — re-reads `/users/me`, which refreshes the cached user and the
    /// membership store.
    private func refreshUserDetails() {
        guard let repository = DependencyContainer.current.resolveIfRegistered((any AuthRepository).self) else { return }
        Task {
            _ = try? await repository.fetchCurrentUser()
        }
    }

    /// `songs.public` — the user-facing payload the backend actually sends
    /// is sparse (`{id, language}`, confirmed against
    /// `src/jobs/scheduled/song.scheduling.js`'s `user` branch), not a full
    /// song row, so unlike Dart (`getSongFromJson(data)` into a Realm
    /// upsert) this doesn't attempt to reconstruct a `Song` domain entity
    /// from it — there isn't enough on the wire to build one. This only
    /// signals "content changed" (Dart's `HomeDataChangedEvent()`) and
    /// mirrors the foreground local notification when the backend asks for
    /// one.
    private func handleSongPublished(_ envelope: RealtimeEnvelope) {
        eventBus.notifyNewContentAvailable()
        guard envelope.showNotification == true else { return }
        let title = envelope.title ?? ""
        let body = envelope.message ?? ""
        Task {
            await notificationScheduler.post(id: UUID().uuidString, title: title, body: body)
        }
    }
}

/// `users.playlist.updated`'s `data` shape — `{id, userId, image,
/// imageVariants}` (`user-playlists.job.js`). Only `id` is read; the others
/// exist purely for documentation of the real wire shape.
private struct PlaylistUpdatedPayload: Decodable, Sendable {
    let id: String
}

/// `verseOfDay.update`'s `data` — `{id, likes, comments, ...}`.
private struct VerseOfDayCountsPayload: Decodable, Sendable {
    let id: String
    let likes: Int?
    let comments: Int?
}

/// `verseOfDay.comment.like`'s `data` — `{commentId, likes, verseOfDayId}`.
private struct VerseOfDayCommentLikePayload: Decodable, Sendable {
    let commentId: String
    let likes: Int
    let verseOfDayId: String
}
