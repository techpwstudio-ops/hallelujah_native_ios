import AVFoundation
import Foundation
import Observation
import UIKit

/// T38 — ports `SongAnalyticsManager` (`lib/services/SongAnalyticsManager.dart`):
/// per-song playback sessions, progress milestones, pause/resume/seek/loop
/// events, folded together with `PlaylistProgressStore.recordPlay` at the
/// same song-change observation point Dart's own `sessionChanged` sits at.
/// Observes `AudioEngine.currentSong`/`.status` via the same self-re-registering
/// `withObservationTracking` pattern `NowPlayingCoordinator` (T32) already
/// established, rather than `AudioEngine` gaining a bespoke closure per
/// lifecycle moment — `status` transitions already cover every path that
/// can pause/resume playback (explicit tap, interruption, route change),
/// so this needs no new integration points on the engine beyond the
/// `onSeek`/`onLoopRestart` closures T38 already added there/on
/// `QueueController`.
///
/// Scope notes (flagged, not silently dropped):
/// - `syncToRecentlyPlayedSongApi` (`SongAnalyticsManager.startSession`'s
///   fire-and-forget `sourceId`/`sourceRank`/`searchQuery` POST, which powers
///   the home "Continue Your Journey" rail's resume position) is a SEPARATE
///   backend call from the SQLite/analytics pipeline this file ports — no
///   native `HomeRepository` method for it exists yet, and it isn't named in
///   T38's own roadmap text. Deferred to whichever task builds that rail.
/// - `loop_play_number`/`is_suspected_fraud` are accumulated in memory
///   (`loopPlayNumber`/`dailyLoopCounts` below) and sent only as part of the
///   session's END event, rather than eagerly persisted and re-synced on
///   every loop restart the way Dart's SQLite `UPDATE` does. Dart's eager
///   write exists so a force-quit mid-loop doesn't lose the count; the
///   native gap is that an abandoned (never-ended) session simply reports no
///   loop data at all — consistent with `ANALYTICS_PAYLOAD.md`'s own
///   `ended_at: null` = "still open" contract, not a new failure mode.
/// - Resume-on-launch (reading `last_song_id`/`last_song_position_ms` back
///   and restoring playback into the UI) isn't built here — see
///   `AudioEngine.persistPlaybackPosition`'s doc comment for why. Only the
///   WRITE half (already in `AudioEngine`) ships.
/// - Progress-poll cadence is a flat 2s regardless of foreground/background
///   (Dart throttles to 5s in background to save CPU/battery while a
///   suspended isolate can't run anyway) — this engine's own background
///   execution comes from the `.playback` audio session category, which has
///   no equivalent suspension concern, so the simpler flat interval doesn't
///   cost correctness, only a small, unmeasured amount of extra background
///   CPU relative to Dart's own throttle.
@MainActor
final class PlaybackAnalyticsRecorder {
    private static let progressMilestones = [10, 25, 50, 75, 95]
    private static let maxDailyLoopsPerSong = 20
    private static let progressPollInterval: Duration = .seconds(2)

    private let engine: AudioEngine
    private let queueController: QueueController
    private let analytics: any AnalyticsTracking
    private let progressStore: PlaylistProgressStore
    private let qualitySelector: AudioQualitySelector
    private let reachability: any ReachabilityMonitoring

    // Active-session state — mirrors `SongAnalyticsManager`'s own instance fields.
    private var sessionID: String?
    private var songID: String?
    private var creatorID: String?
    private var contentType: String?
    private var audioQuality: String?
    private var loopPlayNumber = 0
    private var isSuspectedFraud = false
    private var firedMilestones: Set<Int> = []
    private var songDurationMS = 0
    private var lastKnownPositionMS = 0

    private var dailyLoopCounts: [String: Int] = [:]
    private var lastObservedStatus: AudioEngine.Status = .idle
    private var wasPaused = false
    private var isOffline = false
    private var progressTask: Task<Void, Never>?

    /// Feeds the one-shot store review prompt (`ReviewPromptService`): called
    /// with `(listenedMs, totalDurationMs)` when a play session ends having
    /// played any audio (`SongAnalyticsManager`'s `onListenEnded` hook, `ai` branch).
    var onListenEnded: (@MainActor (Int, Int) -> Void)?

    init(
        engine: AudioEngine,
        queueController: QueueController,
        analytics: any AnalyticsTracking,
        progressStore: PlaylistProgressStore,
        qualitySelector: AudioQualitySelector,
        reachability: any ReachabilityMonitoring
    ) {
        self.engine = engine
        self.queueController = queueController
        self.analytics = analytics
        self.progressStore = progressStore
        self.qualitySelector = qualitySelector
        self.reachability = reachability

        engine.onSeek = { [weak self] from, to in
            self?.recordSeek(from: from, to: to)
        }
        queueController.onLoopRestart = { [weak self] in
            self?.recordLoopRestart()
        }
        // A second `ReachabilityMonitoring` instance, independent of
        // `NetworkStatusStore`'s (T19) — that one is View-layer `@State`,
        // constructed by `AppShellView`, not resolvable from this
        // composition-root-level singleton. `ReachabilityMonitoring`'s own
        // DI registration already anticipates "a fresh instance per resolve
        // is equivalent" for exactly this kind of second, independent
        // consumer.
        reachability.start { [weak self] online in
            self?.isOffline = !online
        }

        trackEngine()
    }

    // MARK: - Observation

    private func trackEngine() {
        withObservationTracking {
            _ = engine.currentSong
            _ = engine.status
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyEngineChange()
                self?.trackEngine()
            }
        }
    }

    private func applyEngineChange() {
        let song = engine.currentSong
        let status = engine.status

        if song?.id != songID {
            endActiveSession()
            wasPaused = false
            lastObservedStatus = status
            if let song {
                Task { [weak self] in
                    await self?.startSession(for: song)
                }
            }
            return
        }

        switch status {
        case .paused:
            if lastObservedStatus != .paused, sessionID != nil {
                recordPause()
                wasPaused = true
            }
        case .playing:
            if wasPaused, sessionID != nil {
                recordResume()
                wasPaused = false
            }
        default:
            break
        }
        lastObservedStatus = status
    }

    // MARK: - Session lifecycle (`sessionChanged`/`startSession`/`endSession`)

    private func startSession(for song: Song) async {
        let newSessionID = UUID().uuidString
        sessionID = newSessionID
        songID = song.id
        loopPlayNumber = 0
        isSuspectedFraud = false
        firedMilestones = []
        lastKnownPositionMS = 0

        let playSource = queueController.queue?.source.playerType.rawValue
        creatorID = song.creator?.creatorId
        contentType = song.type
        let primaryGenreID = song.primaryGenre?.genreId
        songDurationMS = (song.duration ?? 0) * 1000
        let quality = await qualitySelector.targetQuality()
        audioQuality = quality.rawValue
        // `OurSession.instance.membership?.subscription` — resolved lazily
        // from the container so the recorder's init (composition-owned)
        // doesn't have to change.
        let subscription = await DependencyContainer.current.resolveIfRegistered(MembershipStore.self)?.membership?.subscription

        analytics.track(PlaybackSessionStartEvent(
            sessionID: newSessionID,
            songID: song.id,
            creatorID: creatorID,
            primaryGenreID: primaryGenreID,
            type: contentType,
            playSource: playSource,
            startedAtMS: Self.nowMS(),
            songDurationMS: songDurationMS,
            audioQuality: audioQuality,
            // No native `Membership`/subscription entity exists yet (grepped
            // `App/Domain/Entities` — none found); that feature isn't built,
            // not merely unwired, so these stay `nil` rather than guessing.
            planID: subscription?.planId,
            planName: subscription?.planName,
            batteryLevel: Self.currentBatteryLevel()
        ))
        insertTrackingEvent(type: .start, positionMS: 0)
        // `SongAnalyticsManager.startSession`: the session row now exists, so
        // CarPlay's Recents tab can refresh to include it.
        CarIntegrationNotifier.recentPlayed()

        // `syncToRecentlyPlayedSongApi`: fire-and-forget source attribution.
        let attribution = queueController.queue?.source
        let queueSongs = queueController.queue?.songs ?? []
        let rankIndex = queueSongs.firstIndex(where: { $0.id == song.id })
        DependencyContainer.current.resolveIfRegistered(HTTPClient.self).map(RecentlyPlayedSyncer.init(client:))?.sync(
            RecentlyPlayedSyncer.Payload(
                songID: song.id,
                sessionID: newSessionID,
                playSource: playSource,
                sourceID: RecentlyPlayedSyncer.sourceID(from: attribution?.id),
                sourceRank: rankIndex.map { $0 + 1 },
                searchQuery: nil
            )
        )

        progressStore.recordPlay(
            playerType: queueController.queue?.source.playerType,
            containerId: queueController.queue?.source.id,
            songID: song.id
        )

        startProgressPolling()
    }

    private func endActiveSession() {
        guard let activeSessionID = sessionID, let activeSongID = songID else { return }
        progressTask?.cancel()
        progressTask = nil

        analytics.track(PlaybackSessionEndEvent(
            sessionID: activeSessionID,
            endedAtMS: Self.nowMS(),
            songEndDurationMS: lastKnownPositionMS,
            loopPlayNumber: loopPlayNumber,
            isSuspectedFraud: isSuspectedFraud
        ))
        insertTrackingEvent(
            type: .end,
            positionMS: lastKnownPositionMS,
            overrideSongID: activeSongID,
            overrideSessionID: activeSessionID
        )

        if lastKnownPositionMS > 0 {
            onListenEnded?(lastKnownPositionMS, songDurationMS)
        }

        sessionID = nil
        songID = nil
        creatorID = nil
        contentType = nil
        audioQuality = nil
        loopPlayNumber = 0
        isSuspectedFraud = false
        firedMilestones = []
        songDurationMS = 0
    }

    // MARK: - Pause / resume / seek / loop

    private func recordPause() {
        insertTrackingEvent(type: .pause, positionMS: Int(engine.currentPosition * 1000))
        progressTask?.cancel()
        progressTask = nil
    }

    private func recordResume() {
        insertTrackingEvent(type: .resume, positionMS: Int(engine.currentPosition * 1000))
        // Milestones already fired stay fired — matches `resume()`'s own
        // comment in `SongAnalyticsManager.dart:336`.
        startProgressPolling()
    }

    private func recordSeek(from: TimeInterval, to: TimeInterval) {
        guard sessionID != nil else { return }
        let type: PlaybackEventKind = to > from ? .seekForward : .seekBackward
        insertTrackingEvent(type: type, positionMS: Int(to * 1000))
    }

    private func recordLoopRestart() {
        guard sessionID != nil, let activeSongID = songID else { return }
        loopPlayNumber += 1
        let dayKey = Self.todayKey(for: activeSongID)
        let count = (dailyLoopCounts[dayKey] ?? 0) + 1
        dailyLoopCounts[dayKey] = count
        trimLoopCounts()
        isSuspectedFraud = count > Self.maxDailyLoopsPerSong
    }

    // MARK: - Progress milestones

    private func startProgressPolling() {
        progressTask?.cancel()
        guard songDurationMS > 0 else { return }
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.progressPollInterval)
                guard !Task.isCancelled else { return }
                self?.checkProgressMilestones()
            }
        }
    }

    private func checkProgressMilestones() {
        guard sessionID != nil, songDurationMS > 0 else { return }
        let positionMS = Int(engine.currentPosition * 1000)
        lastKnownPositionMS = positionMS
        let completionPercent = Int(Double(positionMS) / Double(songDurationMS) * 100)
        for milestone in Self.progressMilestones where completionPercent >= milestone && !firedMilestones.contains(milestone) {
            firedMilestones.insert(milestone)
            insertTrackingEvent(type: .progress, positionMS: positionMS)
        }
    }

    // MARK: - Event insert (`_insertPlaybackEvent`)

    private func insertTrackingEvent(
        type: PlaybackEventKind,
        positionMS: Int,
        overrideSongID: String? = nil,
        overrideSessionID: String? = nil
    ) {
        let id = UUID().uuidString
        analytics.track(PlaybackTrackingEvent(
            id: id,
            eventID: id,
            sessionID: overrideSessionID ?? sessionID ?? "",
            songID: overrideSongID ?? songID ?? "",
            creatorID: creatorID,
            type: contentType,
            eventType: type,
            positionMS: positionMS,
            appState: Self.currentAppState(),
            networkState: isOffline ? "offline" : "online",
            audioQuality: audioQuality,
            batteryLevel: Self.currentBatteryLevel(),
            outputDeviceName: Self.currentOutputDeviceName(),
            eventTimeMS: Self.nowMS()
        ))
        lastKnownPositionMS = positionMS
    }

    // MARK: - Helpers

    private static func nowMS() -> Int {
        Int(Date().timeIntervalSince1970 * 1000)
    }

    private static func currentAppState() -> String {
        UIApplication.shared.applicationState == .background ? "background" : "foreground"
    }

    /// `BatteryService.instance.level` — `UIDevice.current.batteryLevel`
    /// (`-1.0` = unknown, e.g. unsettled monitoring or no battery) reported
    /// as an unclamped 0-100 `Int`, `nil` for unknown, matching Dart's own
    /// nullable `battery_level`. Monitoring itself is already enabled once
    /// for the app's lifetime by `UIDeviceBatteryLevelMonitor` (T31,
    /// DI-registered at launch) — read directly here rather than through
    /// `BatteryLevelMonitoring`, whose only method (`isLowBattery`) collapses
    /// the level to a bool for T31's quality-cap use case, not this file's
    /// need for the raw percentage.
    private static func currentBatteryLevel() -> Int? {
        let level = UIDevice.current.batteryLevel
        guard level >= 0 else { return nil }
        return Int((level * 100).rounded())
    }

    /// `AnalyticsTrackingDataUtils().output?.name` (`FlutterAudioOutput`'s
    /// currently selected route) — `AVAudioSession.currentRoute`'s output
    /// port name is the direct native equivalent, no separate output-tracking
    /// service needed for this one field.
    private static func currentOutputDeviceName() -> String? {
        AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName
    }

    private static func todayDatePrefix() -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)|"
    }

    private static func todayKey(for songID: String) -> String {
        todayDatePrefix() + songID
    }

    private func trimLoopCounts() {
        let prefix = Self.todayDatePrefix()
        dailyLoopCounts = dailyLoopCounts.filter { $0.key.hasPrefix(prefix) }
    }
}
