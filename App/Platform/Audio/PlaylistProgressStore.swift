import Foundation

/// T38 — ports `PlaylistProgressService` (`lib/services/playlist_progress_service.dart`):
/// how far a listener has got through a container, measured in DISTINCT
/// songs played (not total plays — replaying track 3 five times isn't
/// progress, and counting it as such would let a bar creep to 100% on
/// someone who never heard tracks 4 onward). Backs the progress bar on
/// "Continue Your Journey"-style home cards (that UI itself isn't built
/// yet — this is the data layer a future Home task reads from).
///
/// Local-only, matching Dart exactly: has to survive being offline (`playlist_progress.dart:19-22`,
/// playback itself works offline) and update the instant a song starts, not
/// after a feed refresh. `KeyValueStoring.setData`/`data(forKey:)` (the same
/// "small JSON blob" tier `CurrentUserStore` uses) stands in for Dart's
/// Hive-backed `StorageService`.
@MainActor
@Observable
final class PlaylistProgressStore {
    private static let storageKey = "playlist_progress"
    /// Containers kept before the oldest is dropped — insertion-ordered
    /// eviction (first seen is first out), matching Dart's own admittedly-
    /// not-strictly-LRU tradeoff (`playlist_progress_service.dart:30-33`):
    /// "the alternative is rewriting a timestamp on every song start for a
    /// difference no user can perceive."
    private static let maxContainers = 60
    /// Guards one pathological container (a huge catalogue) from growing
    /// the blob unbounded.
    private static let maxSongsPerContainer = 300

    /// `_trackedTypes` (`playlist_progress_service.dart:43-48`): only
    /// containers with a knowable, finite song count get a bar — an
    /// artist's catalogue has no meaningful denominator.
    private static let trackedTypes: Set<PlayerType> = [.companyPlaylist, .album, .season, .userPlaylist]

    private var played: [String: Set<String>] = [:]
    /// Swift's `Dictionary` has no defined iteration order (unlike Dart's
    /// `Map`, which `_played.keys.first` relies on for insertion-ordered
    /// eviction) — this tracks insertion order explicitly so eviction still
    /// drops the genuinely oldest container, not an arbitrary one.
    private var containerOrder: [String] = []
    private let keyValueStore: any KeyValueStoring

    init(keyValueStore: any KeyValueStoring) {
        self.keyValueStore = keyValueStore
        if let data = keyValueStore.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(PersistedState.self, from: data) {
            played = decoded.played
            containerOrder = decoded.order
        }
    }

    private struct PersistedState: Codable {
        let played: [String: Set<String>]
        let order: [String]
    }

    static func tracks(_ playerType: PlayerType?) -> Bool {
        playerType.map(trackedTypes.contains) ?? false
    }

    /// `"<playerTypeName>:<containerId>"` — matches Dart's `keyFor` exactly
    /// so a value written here reads back under the same key a future
    /// screen would use.
    static func key(playerType: String, containerId: String) -> String {
        "\(playerType):\(containerId)"
    }

    /// No-ops for anything untracked, and for a song already recorded
    /// against this container — a looping track writes once, not on every
    /// repeat.
    func recordPlay(playerType: PlayerType?, containerId: String?, songID: String?) {
        guard Self.tracks(playerType), let containerId, !containerId.isEmpty, let songID, !songID.isEmpty else { return }

        let key = Self.key(playerType: playerType!.rawValue, containerId: containerId)
        var songs = played[key] ?? []
        let isNewContainer = played[key] == nil
        guard songs.count < Self.maxSongsPerContainer, songs.insert(songID).inserted else { return }
        played[key] = songs
        if isNewContainer { containerOrder.append(key) }

        if containerOrder.count > Self.maxContainers {
            let oldest = containerOrder.removeFirst()
            played.removeValue(forKey: oldest)
        }
        persist()
    }

    func playedCount(forKey key: String) -> Int {
        played[key]?.count ?? 0
    }

    /// `nil` for an untouched container (a bar pinned at zero is visual
    /// noise), else a 0...1 fraction.
    func progress(forKey key: String, totalSongs: Int) -> Double? {
        guard totalSongs > 0 else { return nil }
        let count = playedCount(forKey: key)
        guard count > 0 else { return nil }
        return min(1, Double(count) / Double(totalSongs))
    }

    /// For sign-out — the next account's home feed must not show how far
    /// the previous one got.
    func clear() {
        played.removeAll()
        containerOrder.removeAll()
        keyValueStore.removeValue(forKey: Self.storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(PersistedState(played: played, order: containerOrder)) else { return }
        keyValueStore.setData(data, forKey: Self.storageKey)
    }
}
