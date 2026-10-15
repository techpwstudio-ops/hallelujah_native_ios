import AVFoundation
import Foundation
import Observation

/// T31 — the low-level playback engine: `AVQueuePlayer` wrapping,
/// `AVAudioSession` lifecycle (category, interruptions, route changes),
/// quality-aware source resolution, and a small resident-item window for a
/// gapless-ish advance between songs.
///
/// Ports the *engine* half of `MyAudioHandler` (`lib/services/audio_service.dart`)
/// only. Queue source tracking, shuffle/repeat mode, and "what's next"
/// resolution live in `PlayerBloc` on the Dart side and, natively, in
/// `QueueController` (T33) — this engine only exposes `repeatOneActive`/
/// `onQueueExhausted` as narrow integration points for that orchestrator,
/// plus `status`/`currentSong`/`currentPosition` for it (and T32's Now
/// Playing wiring) to read. Ads and playback analytics stay out of scope
/// entirely — the same split Dart already has.
///
/// One deliberate simplification vs. Dart: `MyAudioHandler` keeps only ~5
/// `AVPlayerItem`s resident via manual insert/remove window-sliding, an
/// iOS-only optimization justified there by needing to work even while a
/// suspended Dart isolate can't run background logic. A native `AVQueuePlayer`
/// observer isn't subject to that suspension, so this just tops the queue up
/// by one item whenever the current item advances (`AVQueuePlayer` itself
/// already dequeues a finished item once playback moves past it) rather than
/// porting the trim-from-the-front bookkeeping verbatim.
@MainActor
@Observable
final class AudioEngine {
    enum Status: Sendable, Equatable {
        case idle
        case loading
        case playing
        case paused
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var currentSong: Song?
    private(set) var currentPosition: TimeInterval = 0
    private(set) var currentItemDuration: TimeInterval?

    private let player = AVQueuePlayer()
    private let sourceResolver: AudioSourceResolver
    private let qualitySelector: AudioQualitySelector
    private let tokenProvider: any AuthTokenProviding
    private let keyValueStore: any KeyValueStoring
    private let logger = AppLogger(category: .playback)

    /// T38 — narrow integration point for `PlaybackAnalyticsRecorder`
    /// (`seekForward`/`seekBackward` events, `SongAnalyticsManager.seek`),
    /// the same "engine exposes a closure, doesn't know who's listening"
    /// shape `onQueueExhausted` already established for `QueueController`.
    var onSeek: ((_ from: TimeInterval, _ to: TimeInterval) -> Void)?

    /// T69 — narrow integration point for `AdPacingController`'s pacing
    /// counter, the same "engine exposes a closure, doesn't know who's
    /// listening" shape as `onSeek`/`onQueueExhausted` above. Fired at both
    /// places `currentSong` is assigned (a fresh load and a window top-up
    /// advance) — never from inside an ad break itself, since ad playback
    /// never touches this engine's `player`.
    var onSongChanged: ((Song) -> Void)?

    /// T38 — `last_song_id`/`last_song_position_ms` (`audio_service.dart:1637-1680`,
    /// `savePlaybackState`): the resume-position mechanism, independent of
    /// the playback-analytics pipeline entirely (a different, simpler
    /// `StorageService` key pair, not one of the SQLite analytics tables).
    private static let lastSongIDKey = "playback.lastSongID"
    private static let lastSongPositionMSKey = "playback.lastSongPositionMS"

    /// The engine's own linear bookkeeping of "what's resident and where" —
    /// `QueueController` (T33) is the real source of truth for the full
    /// queue/source/shuffle/repeat model one layer up, and drives this pair
    /// via `play(queue:startAt:)`/`adoptQueue(_:currentIndex:)` rather than
    /// this engine tracking any of that itself.
    private var logicalQueue: [Song] = []
    private var logicalIndex = 0

    /// T33 integration points — `QueueController` owns `RepeatMode`/shuffle/
    /// source state and drives these; this engine knows nothing about those
    /// types, only these two narrow signals, matching the split this file's
    /// own top-level doc comment already called for.
    var repeatOneActive = false
    var onQueueExhausted: (() async -> Void)?

    /// T47 — offline playback's local-file-first source check. Same "engine
    /// exposes a closure, doesn't know who's listening" shape as `onSeek`/
    /// `onQueueExhausted` above, rather than this engine taking a
    /// `DownloadEngine` dependency directly: that would couple this file's
    /// `init` to `DownloadEngine`'s own composition-root wiring, which is
    /// out of scope here. `nil` (or a `nil`-returning closure) means "no
    /// downloads exist yet" — `makePlayerItem` falls straight through to
    /// `sourceResolver` in that case, same as today.
    var localFileURLProvider: ((_ songID: String) -> URL?)?

    private var itemSongIDs: [ObjectIdentifier: String] = [:]
    private var retriedViaProxy: Set<String> = []

    private static let residentWindowAhead = 2

    private var wasPlayingBeforeInterruption = false
    nonisolated(unsafe) private var keepAliveTask: Task<Void, Never>?

    nonisolated(unsafe) private var interruptionObserver: NSObjectProtocol?
    nonisolated(unsafe) private var routeChangeObserver: NSObjectProtocol?
    nonisolated(unsafe) private var itemFailureObserver: NSObjectProtocol?
    private var currentItemObservation: NSKeyValueObservation?
    private var timeControlStatusObservation: NSKeyValueObservation?
    nonisolated(unsafe) private var timeObserverToken: Any?

    init(
        proxyBaseURL: URL,
        keyValueStore: any KeyValueStoring,
        batteryMonitor: any BatteryLevelMonitoring,
        connectivityType: any ConnectivityTypeProviding,
        tokenProvider: any AuthTokenProviding
    ) {
        sourceResolver = AudioSourceResolver(proxyBaseURL: proxyBaseURL)
        qualitySelector = AudioQualitySelector(
            keyValueStore: keyValueStore,
            batteryMonitor: batteryMonitor,
            connectivityType: connectivityType
        )
        self.tokenProvider = tokenProvider
        self.keyValueStore = keyValueStore

        configureAudioSession()
        observeInterruptions()
        observeRouteChanges()
        observeItemFailures()
        observePlayerAdvance()
        addTimeObserver()
    }

    deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        if let routeChangeObserver { NotificationCenter.default.removeObserver(routeChangeObserver) }
        if let itemFailureObserver { NotificationCenter.default.removeObserver(itemFailureObserver) }
        if let timeObserverToken { player.removeTimeObserver(timeObserverToken) }
        keepAliveTask?.cancel()
    }

    // MARK: - Public control surface

    /// Loads `queue` starting at `index` and begins playback. The full
    /// replacement-vs-append/"play next" surface T33's orchestrator will
    /// want is deliberately not here yet — this is the minimum a caller
    /// needs to start something playing.
    func play(queue: [Song], startAt index: Int) async {
        guard queue.indices.contains(index) else { return }
        logicalQueue = queue
        logicalIndex = index
        retriedViaProxy.removeAll()
        await loadCurrentAndAheadItems()
        activateSessionAndPlay()
    }

    /// Re-splices the resident ahead-window around a reordered queue
    /// WITHOUT restarting the currently-playing item — used by
    /// `QueueController` for shuffle toggle and manual reorder, neither of
    /// which ever changes WHICH song is current (shuffle pins the current
    /// song first; reorder only moves its position in the array), only
    /// what surrounds it. `play(queue:startAt:)` above is for genuine song
    /// changes (skip/jump), where restarting from position 0 is correct
    /// because it's a different song.
    func adoptQueue(_ queue: [Song], currentIndex: Int) async {
        guard queue.indices.contains(currentIndex) else { return }
        guard queue[currentIndex].id == currentSong?.id else {
            // Defensive fallback — shouldn't happen given the caller's own
            // invariant, but a full reload is still correct if it does.
            await play(queue: queue, startAt: currentIndex)
            return
        }
        logicalQueue = queue
        logicalIndex = currentIndex

        for item in player.items().dropFirst() {
            player.remove(item)
            itemSongIDs[ObjectIdentifier(item)] = nil
        }
        await appendAheadItems(afterLogicalIndex: currentIndex)
    }

    func resume() {
        activateSessionAndPlay()
    }

    func pause() {
        player.pause()
        startKeepAlive()
    }

    /// `StopPlayerEvent` — unlike `pause()`, forgets the song entirely so
    /// every observer (Now Playing, mini player, CarPlay) sees "nothing is
    /// playing" rather than a paused track.
    func stop() {
        persistPlaybackPosition()
        player.pause()
        player.removeAllItems()
        itemSongIDs.removeAll()
        logicalQueue = []
        logicalIndex = 0
        currentSong = nil
        currentPosition = 0
        currentItemDuration = nil
        status = .idle
        stopKeepAlive()
    }

    // Deliberately no bare `skipToNext()`/`skipToPrevious()` primitives here
    // (T31 originally had simple index±1 ones) — `QueueController` (T33)
    // is now the only correct way to navigate a queue, since it alone
    // knows about repeat-mode wraparound and shuffle order; a bare
    // index±1 primitive on this engine would be a footgun for a future
    // caller to bypass that. Skip/jump instead go through `play(queue:startAt:)`
    // above, called by `QueueController` with an already-resolved index.

    func seek(to time: TimeInterval) {
        let from = currentPosition
        player.seek(to: CMTime(seconds: time, preferredTimescale: 1000))
        onSeek?(from, time)
    }

    /// `savePlaybackState` (`audio_service.dart:1670-1680`): called on app
    /// background (`AppShellView`'s `scenePhase` hook, matching
    /// `_applyBackgroundSuspendFlow`'s `audioHandler.savePlaybackState()`
    /// call site) so a force-quit doesn't lose more than a few seconds of
    /// position. Dart's own read-back/restore-on-launch call site
    /// (`RestoreLastSongEvent`, `launch_app.dart:224-228`) is commented out
    /// in the shipped app — this only ports the WRITE half that's actually
    /// active; see `PlaybackAnalyticsRecorder`'s doc comment for why the
    /// restore-on-launch half isn't built here.
    func persistPlaybackPosition() {
        guard let currentSong else { return }
        keyValueStore.setString(currentSong.id, forKey: Self.lastSongIDKey)
        keyValueStore.setString(String(Int(currentPosition * 1000)), forKey: Self.lastSongPositionMSKey)
    }

    /// The one sanctioned way to mutate `currentSong` from outside this
    /// class (otherwise `private(set)`): T44's favourite toggle needs the
    /// mini/full player to reflect an optimistic like/unlike immediately,
    /// without re-fetching or replaying the queue. No-op if nothing is
    /// currently loaded, or if the toggle target isn't the current song
    /// (stale callback from a since-skipped song).
    func setCurrentSongFavorited(_ isFavorited: Bool, songId: String) {
        guard let currentSong, currentSong.id == songId else { return }
        self.currentSong = currentSong.withFavorited(isFavorited)
    }

    // MARK: - Session

    /// Category configured once, matching `AudioSessionConfiguration.music()`
    /// (`audio_session-0.2.4/lib/src/core.dart:548-557`, resolved from Dart's
    /// `session.configure(...)` call in `initAudioService()`): `.playback`
    /// category, `.default` mode, no special options.
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        } catch {
            logger.warning("audio session category configuration failed: \(error)")
        }
    }

    private func activateSessionAndPlay() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            logger.warning("audio session activation failed: \(error)")
        }
        player.play()
        stopKeepAlive()
    }

    /// Ports the reconfigure-then-reactivate step of Dart's interruption-end
    /// handler (`audio_service.dart:228-249`) — "iOS can reset the session
    /// category during suspension," so this restores it explicitly rather
    /// than assuming it survived.
    private func reconfigureAndReactivateSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            logger.warning("audio session reconfigure after interruption failed: \(error)")
        }
    }

    /// Ports `_startKeepAlive` (`audio_service.dart:415-428`): a 30s repeat
    /// of `setActive(true)` while paused, to stop iOS reassigning the Now
    /// Playing session away from this app during a long pause — a real
    /// production workaround, not speculative hardening.
    private func startKeepAlive() {
        keepAliveTask?.cancel()
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                try? AVAudioSession.sharedInstance().setActive(true)
                guard self != nil else { return }
            }
        }
    }

    private func stopKeepAlive() {
        keepAliveTask?.cancel()
        keepAliveTask = nil
    }

    // MARK: - Interruptions

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [weak self] notification in
            guard let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt
            else { return }
            let wasSuspended = (info[AVAudioSessionInterruptionWasSuspendedKey] as? Bool) ?? false
            let optionsValue = (info[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            Task { @MainActor in
                self?.handleInterruption(typeValue: typeValue, wasSuspended: wasSuspended, optionsValue: optionsValue)
            }
        }
    }

    private func handleInterruption(typeValue: UInt, wasSuspended: Bool, optionsValue: UInt) {
        guard let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            guard !wasSuspended else { return }
            wasPlayingBeforeInterruption = (status == .playing)
        case .ended:
            reconfigureAndReactivateSession()
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            guard wasPlayingBeforeInterruption, options.contains(.shouldResume), status != .idle else { return }
            activateSessionAndPlay()
        @unknown default:
            break
        }
    }

    // MARK: - Route changes

    /// Ports `becomingNoisyEventStream` (`audio_service.dart:251-253`,
    /// traced to `audio_session`'s own `.oldDeviceUnavailable`-only filter) —
    /// pause on ANY old-device-unavailable route change, not just a
    /// disambiguated headphone unplug; the package this ports doesn't
    /// disambiguate either.
    private func observeRouteChanges() {
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [weak self] notification in
            guard let info = notification.userInfo,
                  let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt
            else { return }
            Task { @MainActor in
                self?.handleRouteChange(reasonValue: reasonValue)
            }
        }
    }

    private func handleRouteChange(reasonValue: UInt) {
        guard let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue), reason == .oldDeviceUnavailable else { return }
        pause()
    }

    // MARK: - Queue / item loading

    private func loadCurrentAndAheadItems() async {
        guard logicalQueue.indices.contains(logicalIndex) else { return }
        status = .loading

        let currentSongToLoad = logicalQueue[logicalIndex]
        guard let item = await makePlayerItem(for: currentSongToLoad) else {
            status = .failed("Couldn't load this song")
            return
        }

        player.removeAllItems()
        itemSongIDs.removeAll()
        player.insert(item, after: nil)
        itemSongIDs[ObjectIdentifier(item)] = currentSongToLoad.id
        currentSong = currentSongToLoad
        onSongChanged?(currentSongToLoad)
        currentItemDuration = nil
        currentPosition = 0
        // `setAudioSources` (`audio_service.dart:1634-1639`): "save song ID
        // at position 0 so an app kill mid-play still captures which song
        // was last loaded; position is updated again on pause/background."
        keyValueStore.setString(currentSongToLoad.id, forKey: Self.lastSongIDKey)
        keyValueStore.setString("0", forKey: Self.lastSongPositionMSKey)

        await appendAheadItems(afterLogicalIndex: logicalIndex)
    }

    /// Ahead-slot song selection: normally `logicalQueue[index+1...]`, but
    /// under repeat-one every ahead slot is a fresh copy of the CURRENT
    /// song rather than the next one — `AVQueuePlayer`'s own auto-advance
    /// into a duplicate of the current song is indistinguishable from
    /// looping it in place, so this needs no `actionAtItemEnd`/manual-advance
    /// trickery to get single-item repeat working. `topUpWindow`'s existing
    /// index-resolution (matching `currentItem`'s song id back to a
    /// `logicalQueue` index) already handles this correctly too: it
    /// resolves to the same `logicalIndex` every time a duplicate of the
    /// current song becomes current, so the "index" never actually moves
    /// while repeat-one stays engaged for that song.
    private func appendAheadItems(afterLogicalIndex index: Int) async {
        var appended = 0
        var aheadIndex = index + 1
        while appended < Self.residentWindowAhead {
            let aheadSong: Song
            if repeatOneActive {
                aheadSong = logicalQueue[index]
            } else if aheadIndex < logicalQueue.count {
                aheadSong = logicalQueue[aheadIndex]
            } else {
                return
            }
            if let aheadItem = await makePlayerItem(for: aheadSong) {
                player.insert(aheadItem, after: player.items().last)
                itemSongIDs[ObjectIdentifier(aheadItem)] = aheadSong.id
            }
            aheadIndex += 1
            appended += 1
        }
    }

    /// Called whenever `AVQueuePlayer.currentItem` changes (playback
    /// advancing into the next resident item), to keep the window topped up
    /// by one more item ahead. `AVQueuePlayer` auto-removes a finished item
    /// once it moves past it, so there's no matching "trim" step needed here.
    private func topUpWindow() async {
        guard let currentItem = player.currentItem,
              let songID = itemSongIDs[ObjectIdentifier(currentItem)],
              let newIndex = logicalQueue.firstIndex(where: { $0.id == songID })
        else { return }

        logicalIndex = newIndex
        currentSong = logicalQueue[newIndex]
        onSongChanged?(logicalQueue[newIndex])
        currentItemDuration = nil

        let residentCount = player.items().count
        if repeatOneActive {
            // Every ahead slot already holds a copy of the current song;
            // top up exactly one more to replace the one that just became
            // current, same as the normal path below but without advancing
            // past `newIndex`.
            let repeatSong = logicalQueue[newIndex]
            guard let repeatItem = await makePlayerItem(for: repeatSong) else { return }
            player.insert(repeatItem, after: player.items().last)
            itemSongIDs[ObjectIdentifier(repeatItem)] = repeatSong.id
            return
        }

        let nextLogicalIndex = newIndex + residentCount
        guard nextLogicalIndex < logicalQueue.count else { return }

        let nextSong = logicalQueue[nextLogicalIndex]
        guard let nextItem = await makePlayerItem(for: nextSong) else { return }
        player.insert(nextItem, after: player.items().last)
        itemSongIDs[ObjectIdentifier(nextItem)] = nextSong.id
    }

    /// `AVQueuePlayer.currentItem` becomes `nil` once the final resident
    /// item finishes with nothing queued after it (default `.advance`
    /// behavior — unchanged from T31, still relied on here) — the natural
    /// "queue genuinely ran out" signal, as distinct from an ordinary
    /// advance into the next resident item. `QueueController` sets
    /// `onQueueExhausted` to resolve this (repeat-all wraps back to index 0;
    /// repeat-off leaves playback stopped on the last song, matching this
    /// engine's existing no-op-when-nil behavior from before T33).
    private func observePlayerAdvance() {
        currentItemObservation = player.observe(\.currentItem, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self else { return }
                if player.currentItem == nil {
                    await self.onQueueExhausted?()
                } else {
                    await self.topUpWindow()
                }
            }
        }
        timeControlStatusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.applyTimeControlStatus(player.timeControlStatus)
            }
        }
    }

    private func applyTimeControlStatus(_ timeControlStatus: AVPlayer.TimeControlStatus) {
        guard case .failed = status else {
            switch timeControlStatus {
            case .paused: status = .paused
            case .waitingToPlayAtSpecifiedRate: status = .loading
            case .playing: status = .playing
            @unknown default: break
            }
            return
        }
    }

    private func addTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.currentPosition = time.seconds
                if let duration = self.player.currentItem?.duration, duration.isNumeric, duration.seconds.isFinite {
                    self.currentItemDuration = duration.seconds
                }
            }
        }
    }

    // MARK: - Source resolution

    private func makePlayerItem(for song: Song, forceProxy: Bool = false) async -> AVPlayerItem? {
        // T47 — `getAudioSource`'s own priority order (`audio_service.dart:770-800`):
        // "1. Local downloaded file — no network at all," checked strictly
        // before any of `sourceResolver`'s own tiers. `forceProxy` (the
        // item-failure retry path) skips this: a local file that's already
        // failing to play has nothing left to retry via proxy, so that path
        // stays remote-only, same as before. No fallback-to-remote if the
        // local file itself fails to play — Dart has none either, it only
        // ever checks `file.exists()` before committing to the local path.
        if !forceProxy, let localURL = localFileURLProvider?(song.id) {
            let asset = AVURLAsset(url: localURL)
            return AVPlayerItem(asset: asset)
        }

        let quality = await qualitySelector.targetQuality()
        let resolved = forceProxy
            ? sourceResolver.resolveViaProxy(song: song, targetQuality: quality)
            : sourceResolver.resolve(song: song, targetQuality: quality)
        guard let resolved else { return nil }

        var options: [String: Any] = [:]
        if resolved.requiresAuthHeader {
            let token = await tokenProvider.currentAccessToken() ?? ""
            options["AVURLAssetHTTPHeaderFieldsKey"] = [
                "Content-Type": "application/json",
                "Authorization": "Bearer \(token)",
            ]
        }
        let asset = AVURLAsset(url: resolved.url, options: options)
        return AVPlayerItem(asset: asset)
    }

    // MARK: - Error recovery

    /// Ports the shape (not the mechanism) of Dart's load-failure recovery:
    /// where `_setPlayerSourcesWithRetry` retries the SAME URL twice before
    /// giving up, this retries once via the proxy specifically — closing the
    /// gap the research into `audio_service.dart` flagged (no expired-signature-
    /// specific recovery exists there). Only the current item is retried;
    /// a resident lookahead item that fails is left to fail again (and get
    /// this same treatment) once it becomes current.
    private func observeItemFailures() {
        itemFailureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let failedItem = notification.object as? AVPlayerItem else { return }
            let identifier = ObjectIdentifier(failedItem)
            Task { @MainActor in
                await self?.handleItemFailure(identifier: identifier)
            }
        }
    }

    private func handleItemFailure(identifier: ObjectIdentifier) async {
        guard let currentItem = player.currentItem, ObjectIdentifier(currentItem) == identifier,
              let songID = itemSongIDs[identifier],
              let song = logicalQueue.first(where: { $0.id == songID })
        else { return }

        guard !retriedViaProxy.contains(song.id) else {
            logger.warning("playback failed again after proxy retry for song \(song.id)")
            status = .failed("Couldn't play this song")
            return
        }
        retriedViaProxy.insert(song.id)
        logger.warning("playback item failed for song \(song.id); retrying via proxy")

        guard let retryItem = await makePlayerItem(for: song, forceProxy: true) else {
            status = .failed("Couldn't play this song")
            return
        }
        itemSongIDs[ObjectIdentifier(retryItem)] = song.id

        let stillCurrent = player.currentItem.map { ObjectIdentifier($0) == identifier } ?? false
        guard stillCurrent else { return }

        let wasPlaying = status == .playing
        player.replaceCurrentItem(with: retryItem)
        if wasPlaying {
            activateSessionAndPlay()
        }
    }
}
