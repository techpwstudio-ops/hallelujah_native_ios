import Foundation
import Observation

/// T67 — the landing spot for realtime events whose consuming feature has no
/// targeted per-id patch method (`LibraryViewModel` only exposes coarse
/// `load()`/`refresh()`, matching `lib/services/realtime_event_handler.dart`'s
/// own comment that Dart's Realm-backed byId write is what BLoCs react to).
/// A counter-based broadcast, not a boolean, so the same event landing twice
/// in a row still produces an observable change — the exact shape
/// `SignOutSignal` (`Core/Security/SignOutSignal.swift`) already established
/// for this app; this is that same pattern reused for realtime, not a new
/// one invented for this task.
///
/// `verseOfDay*`/`premium*` counters currently have no subscriber — T56
/// (verse of the day) and T61-65 (monetization/family members) don't exist
/// yet. They're wired here anyway, per the real Dart event names, so those
/// future features only need to add an `onChange`/`task(id:)` observer, not
/// touch `RealtimeEventDispatcher` or the socket layer at all.
@MainActor
@Observable
final class RealtimeEventBus {
    /// Bumped by `users.playlist.updated`. `lastUpdatedPlaylistID` is the
    /// playlist's id from the event payload — a playlist-detail view can
    /// compare it against its own id before deciding to `refresh()`, instead
    /// of every open library screen refetching on every playlist's event.
    private(set) var playlistUpdateCount = 0
    private(set) var lastUpdatedPlaylistID: String?

    /// Bumped by `verseOfDay.update`. No consumer yet — see doc comment above.
    private(set) var verseOfDayUpdateCount = 0
    /// Bumped by `verseOfDay.comment.like`. No consumer yet.
    private(set) var verseOfDayCommentLikeCount = 0
    /// Bumped by `verseOfDay.comment.added`. No consumer yet.
    private(set) var verseOfDayCommentAddedCount = 0

    /// Bumped by `premium.member.invite` (Dart: presents an invite-received
    /// sheet). `AppInfrastructureHost` consumes it; `lastPremiumInvite` is the
    /// event's `{inviteId, inviterName, planName}`.
    private(set) var premiumInviteReceivedCount = 0
    private(set) var lastPremiumInvite: InitInviteInfo?
    /// Bumped by `premium.invite.update` (Dart: `familyMembersProvider
    /// .updateInviteStatus(inviteId, status)`). A family-members screen
    /// compares `lastPremiumInviteStatusUpdate` against its own rows.
    private(set) var premiumInviteStatusUpdateCount = 0
    private(set) var lastPremiumInviteStatusUpdate: PremiumInviteStatusUpdate?
    /// Bumped by `premium.update` (Dart: `OurSession.fetchUserDetails()`).
    /// The dispatcher itself also re-fetches the user, which refreshes the
    /// membership store.
    private(set) var premiumUpdateCount = 0

    /// Bumped by `songs.public` (Dart: `HomeDataChangedEvent()`). A future
    /// Home view model can observe this to know its feed is stale.
    private(set) var newContentAvailableCount = 0

    func notifyPlaylistUpdated(id: String) {
        lastUpdatedPlaylistID = id
        playlistUpdateCount += 1
    }

    func notifyVerseOfDayUpdated() { verseOfDayUpdateCount += 1 }
    func notifyVerseOfDayCommentLiked() { verseOfDayCommentLikeCount += 1 }
    func notifyVerseOfDayCommentAdded() { verseOfDayCommentAddedCount += 1 }

    func notifyPremiumInviteReceived(_ invite: InitInviteInfo? = nil) {
        lastPremiumInvite = invite
        premiumInviteReceivedCount += 1
    }

    func notifyPremiumInviteStatusUpdated(_ update: PremiumInviteStatusUpdate? = nil) {
        lastPremiumInviteStatusUpdate = update
        premiumInviteStatusUpdateCount += 1
    }
    func notifyPremiumUpdated() { premiumUpdateCount += 1 }

    func notifyNewContentAvailable() { newContentAvailableCount += 1 }
}

/// `premium.invite.update`'s `data` — `{inviteId, status}`.
struct PremiumInviteStatusUpdate: Sendable, Equatable {
    let inviteId: String
    let status: String
}
