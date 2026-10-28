import Foundation
import Observation

extension Notification.Name {
    /// The signed-in user followed or un-followed artists; `object` is the
    /// `[String]` of creator ids. Lists of followed artists reload on it.
    static let creatorFollowDidChange = Notification.Name("Hallelujah.creatorFollowDidChange")
}

/// The one follow state every artist button reads (creator page, player's
/// creator card and sheet, artist menu), so following or un-following on
/// any screen shows the same on every other one straight away. Dart gets
/// this from its single Realm `Creator` row; here a fetched `Creator` only
/// carries the follow flag as of its own fetch, so each screen asks this
/// store first and falls back to that flag.
@MainActor
@Observable
final class CreatorFollowStore {
    static let shared = CreatorFollowStore()

    private var states: [String: Bool] = [:]

    private init() {}

    /// What a button for `creatorID` shows.
    func isFollowing(_ creatorID: String?, fallback: Bool?) -> Bool {
        if let creatorID, let state = states[creatorID] { return state }
        return fallback == true
    }

    /// The state the user last set for `creatorID`, if any this session.
    func state(for creatorID: String?) -> Bool? {
        creatorID.flatMap { states[$0] }
    }

    /// Optimistic flip before the request, or the revert after a failure
    /// (`nil` forgets it).
    func set(_ isFollowing: Bool?, for creatorID: String) {
        states[creatorID] = isFollowing
    }

    /// The server accepted the change (`CreatorRepository` calls this).
    func record(isFollowing: Bool, creatorIDs: [String]) {
        guard !creatorIDs.isEmpty else { return }
        for id in creatorIDs { states[id] = isFollowing }
        NotificationCenter.default.post(name: .creatorFollowDidChange, object: creatorIDs)
    }

    func clear() {
        states = [:]
    }
}
