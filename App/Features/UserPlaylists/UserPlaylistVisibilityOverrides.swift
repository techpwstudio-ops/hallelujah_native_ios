import Foundation
import Observation

/// The visibility the user just chose for a playlist, held for a few minutes
/// and shown in place of whatever a fetch returns. Every screen that shows a
/// playlist's Public/Private (the playlist page header, its menu, Library
/// rows, search rows) reads through `resolve`, so they all flip together the
/// moment the toggle is tapped, and a list or page that was loaded before the
/// change (and is still on screen or in memory) can't put the old value back.
///
/// The server keeps no cache of these reads (`userPlaylist.controller.js`,
/// `library.controller.js`), so only a value the server confirmed is held: a
/// failed toggle drops the entry and the next fetch shows the truth.
///
/// Also the one place that knows a toggle is in flight. `GET .../visibility`
/// flips the server's value rather than setting one, so two overlapping
/// toggles (the menu reopened before the first answer) can be applied in
/// either order and the older answer would land last; one at a time per
/// playlist keeps the shown value and the server's in step.
@MainActor
@Observable
final class UserPlaylistVisibilityOverrides {
    static let shared = UserPlaylistVisibilityOverrides()

    /// Long enough to cover lists fetched before the change that are still
    /// on screen (search results, a Library page not yet re-fetched).
    private static let holdDuration: TimeInterval = 300

    private var entries: [String: (visibility: String, until: Date)] = [:]
    private var toggling: Set<String> = []

    /// Internal (not private) so tests can use their own store.
    init() {}

    /// `nil` drops the override.
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

    /// Claims the playlist for one toggle; `false` while another is in flight.
    func beginToggle(for playlistID: String) -> Bool {
        guard !toggling.contains(playlistID) else { return false }
        toggling.insert(playlistID)
        return true
    }

    func endToggle(for playlistID: String) {
        toggling.remove(playlistID)
    }

    func isToggling(_ playlistID: String) -> Bool {
        toggling.contains(playlistID)
    }

    func clear() {
        entries = [:]
        toggling = []
    }
}
