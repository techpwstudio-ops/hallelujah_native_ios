import Foundation

/// T33 — the queue model: canonical ordered queue, source attribution,
/// shuffle, repeat mode, reorder. Ports the queue-orchestration half of
/// `PlayerBloc` (`lib/blocs/player/bloc.dart`) that `AudioEngine` (T31)
/// explicitly left out — `AudioEngine` only knows "play this list starting
/// here" and two narrow signals (`repeatOneActive`, `onQueueExhausted`);
/// this type is what decides WHAT that list is and drives `AudioEngine`
/// through it, the same split Dart already has between `PlayerBloc` and
/// `MyAudioHandler`.
///
/// **Scope note — two things Dart has that this deliberately does NOT
/// build yet, both flagged rather than silently dropped:**
/// - "Add a whole container to the queue" (`AddSourceToQueueEvent`,
///   Dart's own narrower `QueueSource` type) and "play next" (single-song
///   insert, `AddToQueueEvent`) — no UI anywhere in the native app has a
///   trigger for either yet (no context-menu/queue-button exists before
///   T35/T37), and they're not named in T33's own roadmap text ("Queue
///   state, source tracking, shuffle, repeat modes, reorder, up-next").
///   "Up-next" itself needs no separate data structure per the research
///   into `QueuePage` — it's just `queue.songs` sliced from `currentIndex`
///   onward, a view a future screen can build directly off `queue`.
/// - Automatic hand-off to related content when a repeat-off queue plays
///   to its natural end (`_continueWithRelatedContent`, bloc.dart), and the
///   bounded queue-history stack that exists solely to let Previous walk
///   back out of one. This needs a recommendation-fetch backend call this
///   codebase doesn't have yet and isn't named in progress.md's T31-T39
///   breakdown — out of scope, not an oversight.
@MainActor
@Observable
final class QueueController {
    private static let repeatModeKey = "queue.repeatMode"
    private static let previousTrackRestartThreshold: TimeInterval = 3

    private(set) var queue: PlaybackQueue?
    private(set) var isShuffled = false
    private(set) var repeatMode: RepeatMode = .off

    /// T38 — `recordLoopRestart` (`SongAnalyticsManager`) fires whenever
    /// "the player bloc detects the current song restarted from the
    /// beginning" under repeat-all OR repeat-one. This only covers the
    /// repeat-ALL wrap-at-queue-end case (`handleQueueExhausted` below) —
    /// the only one with a clean, unambiguous native signal. Repeat-ONE's
    /// restart is entirely internal to `AudioEngine`'s ahead-window
    /// same-song-duplicate trick (`appendAheadItems`/`topUpWindow`), with no
    /// externally observable moment a listener could hook without either
    /// extending that engine's public surface or a position-jump heuristic
    /// that would also misfire on an ordinary manual seek-backward — left
    /// unfired for that case rather than shipped as an unreliable guess.
    var onLoopRestart: (() -> Void)?

    /// Pre-shuffle snapshot for restoring order — `_unshuffledQueue`
    /// (`bloc.dart:1912`). Only used to restore if it's still the same
    /// length as the current queue; a manual reorder that happened while
    /// shuffled is discarded on un-shuffle, matching Dart's own same gap
    /// (see `reorder(from:to:)`'s doc comment).
    private var unshuffledSongs: [Song]?

    private let engine: AudioEngine
    private let keyValueStore: any KeyValueStoring

    init(engine: AudioEngine, keyValueStore: any KeyValueStoring) {
        self.engine = engine
        self.keyValueStore = keyValueStore

        if let stored = keyValueStore.string(forKey: Self.repeatModeKey), let restored = RepeatMode(rawValue: stored) {
            repeatMode = restored
        }
        engine.repeatOneActive = (repeatMode == .one)
        engine.onQueueExhausted = { [weak self] in
            await self?.handleQueueExhausted()
        }
        // `isShuffled` is deliberately NOT restored from anywhere — always
        // starts `false`, matching `_onInit`'s explicit reset
        // (`bloc.dart:368-373`: "inheriting it silently from a session days
        // ago makes a playlist look like it came back wrong").
    }

    // MARK: - Starting playback

    /// Loads a fresh queue and starts playback at `songs[startIndex]`.
    /// Every entry point (home row, search result, playlist "Play",
    /// creator profile row) is expected to construct `source` itself the
    /// same way Dart's `PlaySongEvent{playerType, playerId, songs,
    /// contextTitle}` does at each tap site (`base_media_list_tile.dart:48-58`
    /// and its peers) — there's no shared "queue builder" beyond this one
    /// entry point, matching Dart's own lack of one.
    func play(songs: [Song], startIndex: Int, source: QueueAttribution) async {
        guard songs.indices.contains(startIndex) else { return }
        let startSongID = songs[startIndex].id
        let ordered = isShuffled ? Self.shuffle(songs, keepFirst: startSongID) : songs
        let index = ordered.firstIndex(where: { $0.id == startSongID }) ?? 0
        unshuffledSongs = isShuffled ? songs : nil
        queue = PlaybackQueue(songs: ordered, currentIndex: index, source: source)
        await engine.play(queue: ordered, startAt: index)
    }

    // MARK: - Editing the queue

    /// `AddToQueueEvent` (`bloc.dart`) — appends `song` after the existing
    /// entries and keeps what is playing untouched. Returns `false` (and does
    /// nothing) when the song is already queued, which the caller reports by
    /// opening the queue instead, as `showQueueSheet` does. With nothing
    /// queued yet, the song simply starts playing.
    @discardableResult
    func addToQueue(_ song: Song, source: QueueAttribution) async -> Bool {
        await addToQueue([song], source: source) > 0
    }

    /// `AddSourceToQueueEvent` — appends every song not already queued, in
    /// order, and returns how many were added. With nothing queued yet the
    /// songs start playing from the first.
    @discardableResult
    func addToQueue(_ songs: [Song], source: QueueAttribution) async -> Int {
        guard var current = queue else {
            guard !songs.isEmpty else { return 0 }
            await play(songs: songs, startIndex: 0, source: source)
            return songs.count
        }
        let queued = Set(current.songs.map(\.id))
        let fresh = songs.filter { !queued.contains($0.id) }
        guard !fresh.isEmpty else { return 0 }
        current.songs += fresh
        unshuffledSongs? += fresh
        queue = current
        await engine.adoptQueue(current.songs, currentIndex: current.currentIndex)
        return fresh.count
    }

    /// `StopPlayerEvent` — drops the queue and tears playback down, leaving
    /// the app as if nothing had been played this session.
    func clear() {
        queue = nil
        unshuffledSongs = nil
        engine.stop()
    }

    // MARK: - Shuffle

    /// Physically reorders `queue.songs` with the current song pinned
    /// first — NOT an index-mapping layer kept alongside an untouched
    /// original order. Matches `shuffleQueue` (`bloc.dart:1990-2000`):
    /// "shuffling is something that happens to what comes NEXT" — the
    /// whole rest of the queue, already-played songs included, becomes one
    /// shuffled tail behind the pinned current song; there's no surviving
    /// "past" vs "future" partition once shuffled.
    func toggleShuffle() async {
        guard var current = queue else {
            isShuffled.toggle()
            return
        }
        isShuffled.toggle()
        if isShuffled {
            unshuffledSongs = current.songs
            let currentSongID = current.currentSong?.id
            current.songs = Self.shuffle(current.songs, keepFirst: currentSongID)
            current.currentIndex = 0
        } else if let unshuffled = unshuffledSongs, unshuffled.count == current.songs.count {
            let currentSongID = current.currentSong?.id
            current.songs = unshuffled
            current.currentIndex = currentSongID.flatMap { id in unshuffled.firstIndex(where: { $0.id == id }) } ?? 0
            unshuffledSongs = nil
        }
        queue = current
        await engine.adoptQueue(current.songs, currentIndex: current.currentIndex)
    }

    private static func shuffle(_ songs: [Song], keepFirst id: String?) -> [Song] {
        let head = id.flatMap { keepID in songs.first(where: { $0.id == keepID }) }
        let rest = songs.filter { $0.id != head?.id }.shuffled()
        guard let head else { return rest }
        return [head] + rest
    }

    // MARK: - Repeat

    /// Cycles off -> all -> one -> off (`_onLoopModeChanged`,
    /// `bloc.dart:2002-2033`) — one button, not 3 independently-selectable
    /// modes. Persisted, matching `StorageService.setString('loopMode', ...)`.
    func cycleRepeatMode() {
        repeatMode = repeatMode.next
        keyValueStore.setString(repeatMode.rawValue, forKey: Self.repeatModeKey)
        engine.repeatOneActive = (repeatMode == .one)
    }

    // MARK: - Reorder

    /// `_onReorder` (`bloc.dart:874-884`): remove-then-insert on the
    /// canonical array. Operates on whatever `queue.songs` currently is —
    /// if shuffled, that IS the shuffled order, and this mutates it
    /// directly. `unshuffledSongs` is a separate, untouched snapshot used
    /// only for un-shuffling, so a manual reorder performed while shuffled
    /// does NOT get reflected into it — turning shuffle off afterward
    /// discards the reorder and restores the pre-shuffle order. This
    /// matches Dart's own identical gap (its `_unshuffledQueue` cache has
    /// the same blind spot), not a native regression.
    func reorder(from oldIndex: Int, to newIndex: Int) async {
        guard var current = queue, current.songs.indices.contains(oldIndex), current.songs.indices.contains(newIndex) else { return }
        let currentSongID = current.currentSong?.id
        let item = current.songs.remove(at: oldIndex)
        current.songs.insert(item, at: newIndex)
        if let currentSongID, let resolved = current.songs.firstIndex(where: { $0.id == currentSongID }) {
            current.currentIndex = resolved
        }
        queue = current
        await engine.adoptQueue(current.songs, currentIndex: current.currentIndex)
    }

    // MARK: - Navigation

    /// Always a fresh `AudioEngine.play` (never `adoptQueue`) — unlike
    /// shuffle/reorder, skip/jump always changes WHICH song is current, so
    /// starting it fresh at position 0 is correct, not a restart to avoid.
    func skipToNext() async {
        guard let current = queue,
              let target = Self.resolveSkipTarget(currentIndex: current.currentIndex, songs: current.songs, forward: true, wraps: repeatMode == .all)
        else { return }
        queue?.currentIndex = target
        await engine.play(queue: current.songs, startAt: target)
    }

    /// `SeekToPreviousSongEvent`'s `allowRestart` convention
    /// (`lib/blocs/player/bloc.dart:667-679`, "what every player does"):
    /// more than 3s into the current track, Previous restarts it instead of
    /// moving back one. Lives here now (moved from `NowPlayingCoordinator`,
    /// per that task's own flagged coordination note) since "what does
    /// Previous mean" is squarely a queue-model concern once one exists.
    /// `allowRestart` defaults `true` (the lock-screen/general Previous
    /// button case) but T34's mini player swipe-right passes `false` —
    /// mirroring Dart's own same distinction: `swipe_to_skip.dart` calls
    /// `SeekToPreviousSongEvent(allowRestart: false)` explicitly, "a swipe
    /// back is navigation," always moving back one track under the thumb
    /// rather than restarting the current one.
    func skipToPrevious(allowRestart: Bool = true) async {
        guard let current = queue else { return }
        if allowRestart, engine.currentPosition > Self.previousTrackRestartThreshold {
            engine.seek(to: 0)
            return
        }
        guard let target = Self.resolveSkipTarget(currentIndex: current.currentIndex, songs: current.songs, forward: false, wraps: repeatMode == .all)
        else { return }
        queue?.currentIndex = target
        await engine.play(queue: current.songs, startAt: target)
    }

    /// Direct index jump — `SeekToSongEvent`, the tap-a-row-in-the-queue-screen
    /// case (`queue_page.dart:119-125`).
    func jump(to index: Int) async {
        guard let current = queue, current.songs.indices.contains(index) else { return }
        queue?.currentIndex = index
        await engine.play(queue: current.songs, startAt: index)
    }

    /// Ports `resolveSkipTarget` (`audio_service.dart:2029-2071`) for the
    /// explicit-skip case: walks forward/backward, wrapping only if
    /// `wraps` (repeat-all), stepping over any candidate whose song id
    /// equals the CURRENT song's id (so a duplicate-song queue never
    /// "advances" to another copy of what's already playing), and gives up
    /// (`nil`) if it cycles all the way back to `currentIndex`. Natural
    /// end-of-queue repeat-all wraparound (no explicit skip involved) is a
    /// separate path — `AudioEngine.onQueueExhausted` / `handleQueueExhausted()`
    /// below — and repeat-one is handled entirely inside `AudioEngine`
    /// (`repeatOneActive`), never reaching this resolver at all.
    private static func resolveSkipTarget(currentIndex: Int, songs: [Song], forward: Bool, wraps: Bool) -> Int? {
        let count = songs.count
        guard count > 1, songs.indices.contains(currentIndex) else { return nil }
        let currentSongID = songs[currentIndex].id
        var candidate = currentIndex
        for _ in 0..<count {
            candidate = forward ? candidate + 1 : candidate - 1
            if candidate < 0 || candidate >= count {
                guard wraps else { return nil }
                candidate = forward ? 0 : count - 1
            }
            if candidate == currentIndex { return nil }
            if songs[candidate].id == currentSongID { continue }
            return candidate
        }
        return nil
    }

    /// `AudioEngine`'s natural-end-of-queue signal (queue ran dry with
    /// nothing resident left to auto-advance into). Repeat-all wraps back
    /// to the front (mirrors `_onQueueCompleted`'s use of
    /// `resolveSkipTarget` at genuine queue completion, `bloc.dart:1168-1174`);
    /// repeat-off leaves playback stopped on the last song — `AudioEngine`'s
    /// own pre-T33 behavior when nothing tops up the window further.
    private func handleQueueExhausted() async {
        guard repeatMode == .all, let current = queue, !current.songs.isEmpty else { return }
        // Only a single-song queue wrapping to index 0 is "the same song
        // restarted" (`onLoopRestart`'s own doc comment) — a multi-song
        // repeat-all wrap to a DIFFERENT song at index 0 is ordinary queue
        // navigation, not a loop.
        if current.songs.count == 1 { onLoopRestart?() }
        queue?.currentIndex = 0
        await engine.play(queue: current.songs, startAt: 0)
    }
}
