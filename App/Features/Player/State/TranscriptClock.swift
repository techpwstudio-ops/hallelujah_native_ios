import Observation

/// Publishes which transcript word is being spoken (Phase 2). It is
/// boundary-driven, not a per-frame timer: it reads the playhead, sleeps until
/// the next word or speaking boundary, and reads again. This keeps the work to a
/// few wake-ups a second, which matters for battery.
///
/// The loop runs only while every condition holds: playing, no ad break, the
/// scene active, and at least one of the read-along card or the transcript
/// screen on screen. A seek always recomputes the word, even while paused.
@Observable
@MainActor
final class TranscriptClock {
    private(set) var activeWordIndex: Int?
    private(set) var isSpeaking = false

    @ObservationIgnored private let engine: AudioEngine
    @ObservationIgnored private var index: TimelineIndex?
    @ObservationIgnored private var task: Task<Void, Never>?
    private var isPlaying = false
    private var isAdBreak = false
    private var isSceneActive = true
    private var visibleClients = 0

    init(engine: AudioEngine) {
        self.engine = engine
    }

    /// True when the loop should be running. Exposed for tests.
    var shouldRun: Bool {
        index != nil && isPlaying && !isAdBreak && isSceneActive && visibleClients > 0
    }

    /// Hands over a new episode's index, or `nil` when the episode has no transcript.
    func attach(_ newIndex: TimelineIndex?) {
        index = newIndex
        syncNow()
        reconcile()
    }

    func setPlaying(_ playing: Bool) {
        isPlaying = playing
        reconcile()
    }

    func setAdBreak(_ adBreak: Bool) {
        isAdBreak = adBreak
        reconcile()
    }

    func setSceneActive(_ active: Bool) {
        isSceneActive = active
        reconcile()
    }

    /// Called from `onAppear` of the read-along card and the transcript screen.
    func clientAppeared() {
        visibleClients += 1
        reconcile()
    }

    /// Called from `onDisappear` of the same views.
    func clientDisappeared() {
        visibleClients = max(visibleClients - 1, 0)
        reconcile()
    }

    /// Called when `engine.seekGeneration` changes.
    func seeked() {
        syncNow()
        reconcile()
    }

    private func syncNow() {
        guard let index else {
            activeWordIndex = nil
            isSpeaking = false
            return
        }
        let positionMs = engine.currentPlaybackMs()
        activeWordIndex = index.activeWordIndex(positionMs: positionMs)
        isSpeaking = index.isSpeaking(positionMs: positionMs)
    }

    /// Stops the old loop and starts a new one only when `shouldRun`. The
    /// highlight is kept when the loop stops, so a paused transcript still shows its word.
    private func reconcile() {
        task?.cancel()
        task = nil
        guard shouldRun else { return }
        task = Task { [weak self] in
            await self?.runLoop()
        }
    }

    private func runLoop() async {
        while !Task.isCancelled {
            guard index != nil else { return }
            syncNow()
            let positionMs = engine.currentPlaybackMs()
            guard let wakeMs = index?.nextBoundaryMs(afterPositionMs: positionMs) else { return }
            try? await Task.sleep(for: .milliseconds(max(wakeMs - positionMs, 20)))
        }
    }
}
