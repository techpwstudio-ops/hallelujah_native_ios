import Foundation
import Observation

/// The visibility the user just chose for a playlist, held for a few minutes
/// and shown in place of whatever a fetch returns. Every screen that shows a
/// playlist's Public/Private (the playlist page header, its menu, Library
/// rows, search rows) reads through `resolve`, so they all flip together the
/// moment the toggle is tapped, and a list or page loaded from a response
/// the server built before the change (or cached) can't put the old value
/// back on screen.
@MainActor
@Observable
final class UserPlaylistVisibilityOverrides {
    static let shared = UserPlaylistVisibilityOverrides()

    /// Long enough to outlast any server-side caching of the old value.
    private static let holdDuration: TimeInterval = 300

    private var entries: [String: (visibility: String, until: Date)] = [:]

    private init() {}

    /// `nil` drops the override (a failed toggle with nothing known before).
    func set(_ visibility: String?, for playlistID: String) {
        if let visibility {
            entries[playlistID] = (visibility, Date().addingTimeInterval(Self.holdDuration))
        } else {
            entries[playlistID] = nil
        }
    }

    /// What to show: the user's recent choice if there is one, else `fetched`.
    func resolve(_ fetched: String?, for playlistID: String) -> String? {
        guard let entry = entries[playlistID], entry.until > Date() else { return fetched }
        return entry.visibility
    }

    func clear() {
        entries = [:]
    }
}
