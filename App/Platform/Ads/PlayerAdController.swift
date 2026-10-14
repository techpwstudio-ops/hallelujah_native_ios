import Foundation
import Observation

/// Everything `PlayerAdController` needs from outside itself — a seam, so a
/// test can drive the timeline a second at a time without a server
/// (`PlayerAdSource`, `lib/ads/player_ad_controller.dart`).
@MainActor
protocol PlayerAdSource: AnyObject {
    /// False for a listener who is never shown ads — ads switched off, or a
    /// paying subscriber — so there is nothing to time.
    func canServe() async -> Bool
    func timeline(_ surface: PlayerAdSurface) -> AdTimeline
    /// Songs per takeover: the placement's Pacing field.
    func everyN(_ surface: PlayerAdSurface) -> Int
    /// How much longer a no-fill keeps this placement quiet, in seconds.
    func backoffRemaining(_ surface: PlayerAdSurface) -> TimeInterval
    /// One fresh ad, or nil on no-fill. Never throws.
    func serve(_ surface: PlayerAdSurface) async -> AdCreative?
    /// Loads the ad's picture so it can be shown the moment its turn comes.
    func prepare(_ ad: AdCreative) async -> Bool
}

/// The real thing: the ads repository, and the same artwork warmer the home
/// rails use.
@MainActor
final class RepositoryPlayerAdSource: PlayerAdSource {
    /// Songs per takeover until the server has reported its own number.
    static let defaultEveryN = 1

    private let adsRepository: AdsRepository

    init(adsRepository: AdsRepository) {
        self.adsRepository = adsRepository
    }

    func canServe() async -> Bool { await adsRepository.canServe() }

    func timeline(_ surface: PlayerAdSurface) -> AdTimeline {
        adsRepository.timeline(forPlacement: surface.placement)
    }

    func everyN(_ surface: PlayerAdSurface) -> Int {
        adsRepository.pacingEveryN(forPlacement: surface.placement) ?? Self.defaultEveryN
    }

    func backoffRemaining(_ surface: PlayerAdSurface) -> TimeInterval {
        adsRepository.backoffRemaining(placement: surface.placement, assetType: surface.assetType)
    }

    func serve(_ surface: PlayerAdSurface) async -> AdCreative? {
        let ad = await adsRepository.serve(
            placement: surface.placement,
            assetType: surface.assetType,
            ignoreRetryBackoff: AppConfiguration.current.featureFlags.adsPreviewMode
        )
        if let ad {
            adsRepository.rememberTimeline(forPlacement: surface.placement, load: ad.adLoad)
            adsRepository.rememberPacingEveryN(forPlacement: surface.placement, ad.adLoad.pacingEveryN)
        }
        return ad
    }

    func prepare(_ ad: AdCreative) async -> Bool { await AdArtwork.warm(ad) }
}

/// The audio player's image takeover for as long as the app lives: when the
/// cover gives way to an ad, for how long, and what comes next
/// (`PlayerAdController` + `PlayerAdCubit`).
///
/// It follows the SONG, not a page. The ad it decides on is drawn wherever the
/// listener has the player — over the full player's cover, or as the strip on the
/// mini player — and the clock only runs while one of those is on screen
/// (`surfaceShown`/`surfaceHidden`, the cubit's contract).
///
/// THE CYCLE. For every song that takes part, the cover stands alone for
/// `introSeconds`; then an ad covers it for `displaySeconds`; then the cover
/// comes back for `gapSeconds`; then an ad again — a fresh serve each time —
/// until the song changes. Every showing is its own ad with its own impression
/// token.
///
/// IT RUNS ON PLAYING TIME. The clock is `tick()`, once a second, and only while
/// the song is playing, a surface that can show the ad is on screen (which also
/// means the app is in the foreground), and nothing else is advertising. An ad
/// is asked for `prefetchLeadSeconds` before its turn.
///
/// WHEN ANOTHER AD IS UP. While an audio ad break is running, and while the
/// companion banner it leaves behind is on screen, this has no ad (`setHeldOff`).
@MainActor
@Observable
final class PlayerAdController {
    /// How far ahead of its turn an ad is asked for.
    static let prefetchLeadSeconds = 2
    /// The least wait after an ask came back empty, whatever the server said.
    static let minRetrySeconds = 15
    /// How long a fetched ad may wait for its turn — under the backend's 600 s
    /// impression-token lifetime.
    static let staleAfter: TimeInterval = 5 * 60

    /// The ad to draw over the cover right now, or nil while the cover shows.
    private(set) var ad: AdCreative?
    private(set) var phase: PlayerAdPhase = .organic
    private(set) var surface: PlayerAdSurface = .music
    /// Whether the current song is one the takeover runs on at all — the pacing
    /// field says one song in N.
    private(set) var takesOver = false

    @ObservationIgnored private let source: any PlayerAdSource
    @ObservationIgnored private let pacing: PlayerAdPacing
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let selfTicking: Bool

    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var disposed = false

    @ObservationIgnored private var songID: String?
    @ObservationIgnored private var playing = false
    @ObservationIgnored private var heldOff = false
    /// The surfaces on screen that can draw the ad.
    @ObservationIgnored private var surfaces: Set<UUID> = []
    /// Cached `source.canServe()`, refreshed once per self-driven tick.
    @ObservationIgnored private var canServe = true

    /// Fetched, its picture loaded, waiting for its turn.
    @ObservationIgnored private var ready: AdCreative?
    @ObservationIgnored private var readyAt: Date?
    /// Seconds left in the current phase.
    @ObservationIgnored private var remaining = 0
    /// Seconds before another ask is allowed, after one came back empty.
    @ObservationIgnored private var retryIn = 0
    /// Bumped when the song changes, so a fetch that was out at the time knows it
    /// belongs to a song that is gone and drops what it found.
    @ObservationIgnored private var epoch = 0
    @ObservationIgnored private var fetchingEpoch: Int?

    @ObservationIgnored private weak var engine: AudioEngine?
    @ObservationIgnored private weak var adBreaks: AdPacingController?

    init(
        source: any PlayerAdSource,
        pacing: PlayerAdPacing = PlayerAdPacing(),
        now: @escaping () -> Date = { Date() },
        selfTicking: Bool = true
    ) {
        self.source = source
        self.pacing = pacing
        self.now = now
        self.selfTicking = selfTicking
    }

    private var isFetching: Bool { fetchingEpoch == epoch }

    private var isRunning: Bool {
        !disposed && takesOver && playing && !surfaces.isEmpty && !heldOff
    }

    // MARK: Following the player

    /// Starts following the engine's song and play state and the ad break's
    /// state (`PlayerAdCubit._follow`) for the app's lifetime.
    func bind(engine: AudioEngine, adBreaks: AdPacingController) {
        self.engine = engine
        self.adBreaks = adBreaks
        observe()
    }

    private func observe() {
        guard let engine, let adBreaks else { return }
        // Only the player's own state is tracked here; applying it mutates this
        // controller, which must not be read inside the tracking closure.
        let (song, isPlaying, isAdUp) = withObservationTracking {
            (engine.currentSong, engine.status == .playing, adBreaks.isAdUp)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        follow(song: song, isPlaying: isPlaying, isAdUp: isAdUp)
    }

    /// Tells the controller everything it takes from the player. The song comes
    /// first: it decides whether the controller is running at all, and what the
    /// others then start.
    private func follow(song: Song?, isPlaying: Bool, isAdUp: Bool) {
        if let song {
            onSong(song.id, isEpisode: song.isEpisode)
        } else {
            onNoSong()
        }
        setPlaying(isPlaying)
        setHeldOff(isAdUp)
    }

    // MARK: Surfaces

    /// A surface that can draw the ad has come on screen. Safe to call again
    /// for the same token.
    func surfaceShown(_ token: UUID) {
        guard !disposed, surfaces.insert(token).inserted else { return }
        syncTimer()
    }

    /// The surface is gone, or something is covering it. Safe to call for one
    /// that was never shown.
    func surfaceHidden(_ token: UUID) {
        guard surfaces.remove(token) != nil else { return }
        syncTimer()
    }

    // MARK: Inputs

    /// The song on screen changed. Starts its cycle from the top and drops
    /// whatever the last song had up or on its way. Idempotent for the same song.
    func onSong(_ songID: String, isEpisode: Bool) {
        guard !disposed, songID != self.songID else { return }

        self.songID = songID
        epoch += 1
        surface = PlayerAdSurface.forCover(isEpisode: isEpisode)
        ad = nil
        ready = nil
        readyAt = nil
        phase = .organic
        retryIn = 0
        takesOver = pacing.takesOver(songID, everyN: source.everyN(surface))
        remaining = source.timeline(surface).introSeconds

        syncTimer()
    }

    /// The player has no song any more. Drops everything the last one had up or
    /// on its way, and the next song starts from the top.
    func onNoSong() {
        guard !disposed, songID != nil else { return }

        songID = nil
        epoch += 1
        takesOver = false
        ad = nil
        ready = nil
        readyAt = nil
        phase = .organic
        retryIn = 0
        remaining = 0

        syncTimer()
    }

    /// The song is playing, not paused or buffering to a stop.
    func setPlaying(_ playing: Bool) {
        guard self.playing != playing else { return }
        self.playing = playing
        syncTimer()
    }

    /// Something else is advertising — an audio ad break, or the companion
    /// banner it leaves behind. An ad that is up goes away at once, and the
    /// cover comes back for the gap; one that was only waiting for its turn
    /// waits on.
    func setHeldOff(_ heldOff: Bool) {
        guard self.heldOff != heldOff else { return }
        self.heldOff = heldOff
        if heldOff && phase == .showing { endDisplay() }
        syncTimer()
    }

    /// The listener sent the ad away — its ⋮ menu, or a swipe on the cover. The
    /// cover comes back for the gap, and then there is a new ad.
    func dismiss() {
        guard !disposed, phase == .showing else { return }
        endDisplay()
    }

    // MARK: Clock

    /// One second of the song's playing time. Driven by a task in the app and
    /// called directly in a test.
    func tick() {
        guard isRunning, canServe else { return }

        if retryIn > 0 { retryIn -= 1 }

        if phase == .showing {
            remaining -= 1
            if remaining <= 0 { endDisplay() }
            return
        }

        if remaining > 0 { remaining -= 1 }
        if remaining <= Self.prefetchLeadSeconds { prefetch() }

        // Its turn has come. With no ad ready the cover simply stays up, and the
        // ad takes the next tick it can — a late ad beats a blank one.
        if remaining == 0 { showReady() }
    }

    func dispose() {
        disposed = true
        epoch += 1
        timerTask?.cancel()
        timerTask = nil
        fetchTask?.cancel()
        fetchTask = nil
    }

    /// Lets a test wait for the fetch a `tick()` started.
    func settle() async {
        await fetchTask?.value
    }

    private func syncTimer() {
        guard selfTicking else { return }

        if isRunning {
            guard timerTask == nil else { return }
            timerTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled, let self else { return }
                    self.canServe = await self.source.canServe()
                    self.tick()
                }
            }
        } else {
            timerTask?.cancel()
            timerTask = nil
        }
    }

    private func showReady() {
        guard let candidate = ready, let readyAt else { return }
        ready = nil
        self.readyAt = nil

        // Waited too long for its turn — a listener who paused right here. Drop
        // it rather than show an ad whose impression the server would no longer
        // take; the next tick asks for another.
        if now().timeIntervalSince(readyAt) > Self.staleAfter { return }

        ad = candidate
        phase = .showing
        remaining = source.timeline(surface).displaySeconds
        pacing.markDisplayed()
    }

    private func endDisplay() {
        ad = nil
        phase = .organic
        remaining = source.timeline(surface).gapSeconds
    }

    private func prefetch() {
        guard ready == nil, !isFetching, retryIn <= 0 else { return }

        fetchingEpoch = epoch
        let epoch = epoch
        let surface = surface
        fetchTask = Task { [weak self] in
            await self?.fetch(epoch: epoch, surface: surface)
        }
    }

    private func fetch(epoch: Int, surface: PlayerAdSurface) async {
        var fetched = await source.serve(surface)

        // The server only answers with a format the placement accepts, but a
        // creative of the wrong shape laid over the cover would be cropped to it
        // — and an ad nobody can read is worse than no ad.
        if let candidate = fetched, candidate.assetType != surface.assetType { fetched = nil }
        if let candidate = fetched, !(await source.prepare(candidate)) { fetched = nil }

        // The song changed while the request was out. What it found was for a
        // cover that is gone.
        guard !disposed, epoch == self.epoch else { return }

        fetchingEpoch = nil
        guard let found = fetched else {
            retryIn = max(Int(source.backoffRemaining(surface).rounded(.up)), Self.minRetrySeconds)
            return
        }

        ready = found
        readyAt = now()
    }
}
