import AVFoundation
import Foundation
import UIKit
import Observation

/// What an ad break needs of the playback engine, and no more, so the break's
/// decisions can be driven in a test without audio hardware. `AudioEngine` is
/// the one real conformer.
@MainActor
protocol AdBreakEngine: AnyObject {
    var status: AudioEngine.Status { get }
    var currentSong: Song? { get }
    /// A song that plays again and again with no other song between its plays.
    var isLoopingOneSong: Bool { get }
    var isPlaybackHeld: Bool { get set }
    var onSongChanged: ((Song) -> Void)? { get set }
    var onInterruptionEnded: ((_ shouldResume: Bool) -> Void)? { get set }
    func pause()
    func resume()
}

extension AudioEngine: AdBreakEngine {}

/// Ports the player ad-break slice of `PlayerBloc` (`lib/blocs/player/bloc.dart`):
/// `_maybeStartAdBreak`/`_fetchBreakCreative` for asking,
/// `_onAdBreakStarted`/`_onAdBreakSkipped`/`_onAdBreakPauseToggled`/
/// `_endAdBreak`/`_playAdCreative` for the break's own lifecycle, and
/// `openAdAction` (`lib/ads/ad_action.dart`) for the CTA. One
/// `AdPacingController` per `AudioEngine`, wired the same "engine fires a
/// callback, this subscribes to it" way `onSeek` already works for other
/// listeners — not a method on `AudioEngine` itself, matching that file's
/// own "ads stay out of scope" boundary, now narrowed to "stay a separate
/// observer" now that T69 exists.
///
/// One native simplification vs. Dart: a single `AVPlayer` plays BOTH
/// `audio_ad` and `reel_video` creatives here (`reel_video` additionally
/// renders through a video surface in `AdBreakView`) — Dart needs two
/// separate throwaway players (`just_audio` + `video_player`) because it has
/// no single engine covering both formats; `AVPlayer` already does, so this
/// uses one completion/progress mechanism (`AVPlayerItemDidPlayToEndTime` +
/// a periodic time observer) instead of porting Dart's per-format split.
///
/// Also NOT ported: the break bank and `_preloadAdCreative`'s preload-then-
/// switch phase. Dart fetches a break ahead of the boundary and loads its
/// player before the song ends; here a break is asked for when the song
/// changes and its player is built when the answer arrives, so the first
/// frame can still be on its way when the break opens. A reel draws a spinner
/// until it is, and the startup watchdog gives up on a creative that never
/// gets going.
///
/// Each format is asked on its own placement (`AdBreakFill`):
/// `audio_between_tracks` for `audio_ad` and `reel_between_tracks` for
/// `reel_video`, taking turns, so the dashboard can price, cap and switch off
/// one without the other. An ad that is served and then never reaches the
/// screen is reported through `AdsRepository.reportNotShown`.
///
/// `lingerAfterDismiss` (`_endAdBreak`'s `companionAd`/`showCompanionBanner`
/// branch) is ported: a creative that asked to linger and has a companion
/// picture leaves `companionAd` up with `showCompanionBanner` true when its
/// break ends, which `AdCompanionBanner` draws over the full player until the
/// listener closes it (`dismissCompanion()`).
@MainActor
@Observable
final class AdPacingController {
    private let adsRepository: AdsRepository
    private let engine: any AdBreakEngine

    private(set) var isAdBreak = false
    private(set) var currentAd: AdCreative?
    private(set) var adPosition: TimeInterval = 0
    private(set) var adTotalDuration: TimeInterval = 0
    private(set) var adSkipUnlocksAt: Date?

    /// How far the current break has got, and the pause its player is in. The
    /// rules live in `AdBreakProgress` and `AdPauseState`; this class feeds them
    /// what the player reports.
    private var progress = AdBreakProgress()
    private var pauseState = AdPauseState()

    var isAdPaused: Bool { pauseState.isPaused }

    /// Width over height of the playing video, 0 until the item has reported
    /// its shape. `ReelAdBreak` sizes the video from it and shows a spinner
    /// while it is 0 — it never guesses a shape.
    var adVideoAspectRatio: CGFloat { progress.videoAspectRatio }

    /// Whether the item has loaded far enough to show. False while the first
    /// frame is still coming, which is when the break draws its spinner.
    var isAdReady: Bool { progress.itemIsReady }

    /// `PlayerBlocState.companionAd` / `showCompanionBanner` — the ad left
    /// behind by a break whose creative had `lingerAfterDismiss`.
    private(set) var companionAd: AdCreative?
    private(set) var showCompanionBanner = false

    /// Not `private` — `AdBreakView` reads this directly to give a `reel_video`
    /// creative's picture (`ReelVideoSurface`) its player; everything else
    /// about ad playback stays internal to this controller.
    private(set) var adPlayer: AVPlayer?
    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var sizeObservation: NSKeyValueObservation?
    private var playerStateObservation: NSKeyValueObservation?
    private var startupWatchdog: Task<Void, Never>?

    /// Bumped whenever a creative starts or stops, so a callback from one that
    /// has already ended can tell it is stale.
    private var breakGeneration = 0

    /// How long a creative gets to become playable before the break gives up on
    /// it — a held song and a spinner forever is worse than no ad. A test shortens
    /// it through the initializer; nothing else does.
    static let defaultStartupTimeout: Duration = .seconds(10)
    private let startupTimeout: Duration

    /// Which format `maybeStartAdBreak` asks for first; each ask moves it on,
    /// so audio and reel breaks take turns (`_breakFormatTurn`).
    private var breakFormatTurn = 0
    private var adBreakFetchInFlight = false

    init(
        adsRepository: AdsRepository,
        engine: any AdBreakEngine,
        startupTimeout: Duration = AdPacingController.defaultStartupTimeout
    ) {
        self.adsRepository = adsRepository
        self.engine = engine
        self.startupTimeout = startupTimeout
        engine.onSongChanged = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.maybeStartAdBreak() }
        }
        engine.onInterruptionEnded = { [weak self] shouldResume in
            self?.adInterruptionEnded(shouldResume: shouldResume)
        }
    }

    /// An audio ad break, or the companion banner it leaves behind — the
    /// condition `PlayerAdCubit._adIsUp` holds the image takeover off on.
    var isAdUp: Bool {
        isAdBreak || (showCompanionBanner && companionAd?.companionImageUrl != nil)
    }

    /// `_onDismissCompanionAd` (`DismissCompanionAdEvent`).
    func dismissCompanion() {
        guard showCompanionBanner || companionAd != nil else { return }
        showCompanionBanner = false
        companionAd = nil
    }

    /// `dismissAdBreakIfSkippable` (`ad_break_dismiss.dart`): the ⋮ menu's
    /// "Close ad" on the player surfaces ends the break only if the creative's
    /// own skip lock has already opened — it is not a way around
    /// `skipAfterSec`. Returns whether the break was actually ended.
    @discardableResult
    func dismissIfSkippable() -> Bool {
        guard isAdBreak, canSkip else { return false }
        skip()
        return true
    }

    var canSkip: Bool {
        guard let adSkipUnlocksAt else { return false }
        return Date() >= adSkipUnlocksAt
    }

    /// `_maybeStartAdBreak` (`bloc.dart`) — asks the server for a break at a
    /// song boundary.
    ///
    /// The device no longer counts songs to decide when: how often a listener
    /// hears a break is the ads dashboard's to say (the placement's pacing and
    /// frequency caps), and a count kept here silently overrode it. Every song
    /// change asks; a no-fill is remembered by `AdsRepository`'s per-format
    /// backoff, so the asking stays at most one request a minute per format.
    ///
    /// `force` only lifts that backoff, and only in preview — the serve, no-fill
    /// handling and in-flight guard are identical either way.
    func maybeStartAdBreak(force: Bool = false) async {
        guard !isAdBreak, !adBreakFetchInFlight else { return }

        let preview = force && AppConfiguration.current.featureFlags.adsPreviewMode
        // A song on repeat never ends into another one: each play is a song
        // change, but none is a boundary to put a break on, and a break at every
        // loop would be the same ad over and over (`_breakBlockedReason`).
        guard preview || !engine.isLoopingOneSong else { return }
        let turn = breakFormatTurn
        breakFormatTurn = (turn + 1) % AdBreakFill.assetTypes.count

        adBreakFetchInFlight = true
        defer { adBreakFetchInFlight = false }

        // A break names the format it asks for and the placement that format
        // lives on, and never leaves the choice to the server: a placement that
        // also accepts pictures would hand back a PNG the break cannot play, and
        // a song gets one chance at its boundary.
        let ad = await AdBreakFill.serveBreak(
            start: turn,
            serve: { placement, assetType in
                await adsRepository.serve(placement: placement, assetType: assetType, ignoreRetryBackoff: preview)
            },
            onUnplayable: { unplayable in
                adsRepository.reportNotShown(unplayable, AdBreakFill.unplayableReason(unplayable))
            }
        )

        // Only a missing soundtrack / video is a no-fill. A picture is optional:
        // the server sends `squareImageUrl` only when the same campaign also has
        // an image creative booked, so requiring one silently dropped every
        // plain audio ad — the break draws a glyph for an ad without art.
        guard let ad else { return }
        startAdBreak(with: ad)
    }

    /// Preview-only manual trigger (`ForceAdBreakEvent`/`_onForceAdBreak`) —
    /// guarded here too, same as Dart's own double guard, so a production
    /// build can't start a break this way no matter what calls it.
    func forcePreviewAdBreak() {
        guard AppConfiguration.current.featureFlags.adsPreviewMode else { return }
        guard engine.currentSong != nil else { return }
        Task { await maybeStartAdBreak(force: true) }
    }

    /// `_onAdBreakStarted` (`bloc.dart`).
    private func startAdBreak(with ad: AdCreative) {
        // Another break took the slot while this ad was being fetched: it was
        // served and will not be shown, which only the app can tell the server.
        // Nothing reaches this today — a second ask is turned away while one is
        // in flight — so this holds the line for a trigger added later: a break
        // already under way must never be overwritten, and a served ad is never
        // dropped without a word.
        guard !isAdBreak else {
            adsRepository.reportNotShown(ad, .superseded)
            return
        }
        // The listener paused or stopped the music while this ad was being
        // fetched. A break would hold nothing back, and its end resumes the
        // music: it would start what they had just stopped.
        guard engine.status == .playing || engine.status == .loading else {
            adsRepository.reportNotShown(ad, .superseded)
            return
        }
        // Held for the whole break, so a song the listener picks meanwhile is
        // queued behind the ad instead of playing over it (`endAdBreak` lifts it).
        engine.isPlaybackHeld = true
        engine.pause()

        currentAd = ad
        adPosition = 0
        adTotalDuration = TimeInterval(ad.durationSec ?? 0)
        adSkipUnlocksAt = ad.skipAfterSec.map { Date().addingTimeInterval(TimeInterval($0)) }
        progress = AdBreakProgress()
        pauseState = AdPauseState()
        isAdBreak = true

        playAdCreative(ad)
    }

    /// `_playAdCreative` (`bloc.dart`) — see this file's own doc comment on why
    /// one `AVPlayer` covers both formats here.
    ///
    /// The impression is NOT sent here. It is sent once the creative is really
    /// there to be had (`confirmImpressionIfShown`): sending it at `play()`
    /// counted a reel that then failed to decode, and a listener who never saw
    /// it. An audio ad counts when it can play; a reel waits until its picture
    /// has been on screen (`reelWasSeen`).
    private func playAdCreative(_ ad: AdCreative) {
        guard let urlString = ad.assetUrl, let url = URL(string: urlString) else {
            adsRepository.reportNotShown(ad, .assetMissing)
            endAdBreak()
            return
        }

        breakGeneration += 1
        let generation = breakGeneration

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        adPlayer = player

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.adItemPlayedToEnd(generation: generation) }
        }

        // KVO callbacks are not main-actor isolated. Under Swift 6 a closure
        // inferred as main-actor and then called from another thread traps, so
        // these are `@Sendable` like `AudioEngine`'s, and hand over plain values
        // and a generation number, never the creative or the item: a callback
        // from a break that has already ended must find nothing to act on.
        statusObservation = item.observe(\.status, options: [.initial, .new]) { @Sendable [weak self] item, _ in
            let status = item.status
            Task { @MainActor in self?.itemStatusChanged(status, generation: generation) }
        }
        sizeObservation = item.observe(\.presentationSize, options: [.initial, .new]) { @Sendable [weak self] item, _ in
            let size = item.presentationSize
            Task { @MainActor in self?.itemSizeChanged(size, generation: generation) }
        }
        playerStateObservation = player.observe(\.timeControlStatus, options: [.new]) { @Sendable [weak self] _, _ in
            Task { @MainActor in self?.adPlayerStateChanged(generation: generation) }
        }

        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: CMTimeScale(NSEC_PER_SEC)),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            adPosition = time.seconds
            let duration = item.duration.seconds
            if duration.isFinite, duration > 0 {
                adTotalDuration = duration
            }
        }

        let timeout = startupTimeout
        startupWatchdog = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.startupTimedOut(generation: generation)
        }

        player.play()
    }

    private func itemStatusChanged(_ status: AVPlayerItem.Status, generation: Int) {
        guard generation == breakGeneration, isAdBreak, let ad = currentAd else { return }
        switch status {
        case .readyToPlay:
            progress.itemBecameReady()
            startupSettled(ad)
        case .failed:
            failBreak(ad)
        default:
            break
        }
    }

    private func itemSizeChanged(_ size: CGSize, generation: Int) {
        guard generation == breakGeneration, isAdBreak, size.width > 0, size.height > 0 else { return }
        progress.itemReportedSize(size)
        if let ad = currentAd { startupSettled(ad) }
    }

    private func adItemPlayedToEnd(generation: Int) {
        guard generation == breakGeneration else { return }
        endAdBreak()
    }

    private func startupTimedOut(generation: Int) {
        guard generation == breakGeneration, isAdBreak, let ad = currentAd, !progress.isUnderway(ad) else { return }
        failBreak(ad)
    }

    /// The creative will not play: say so (unless it already counted as shown)
    /// and give the listener their song back.
    private func failBreak(_ ad: AdCreative) {
        if let reason = progress.notShownReason(afterFailureOf: ad) {
            adsRepository.reportNotShown(ad, reason)
        }
        endAdBreak()
    }

    /// The startup is over: stop timing it, and count the impression if the
    /// rest of what it takes is already there.
    private func startupSettled(_ ad: AdCreative) {
        guard progress.isUnderway(ad) else { return }
        startupWatchdog?.cancel()
        startupWatchdog = nil
        confirmImpressionIfShown(ad)
    }

    /// A reel's picture has been on screen, in a foreground app, long enough to
    /// count (`ReelAdBreak`). A reel plays whether or not anyone is looking at
    /// it — the full player can be down at the mini player — so its impression
    /// waits for this: an audio ad is heard the moment it plays, a reel has to
    /// be seen.
    func reelWasSeen() {
        guard isAdBreak, let ad = currentAd, ad.isReel else { return }
        progress.pictureWasSeen()
        confirmImpressionIfShown(ad)
    }

    /// Sends the impression once the creative is genuinely there to be had: the
    /// item can play and, for a reel, its picture has been seen.
    private func confirmImpressionIfShown(_ ad: AdCreative) {
        guard progress.shouldCountImpression(ad) else { return }
        progress.impressionWasSent()
        adsRepository.trackImpressionOnce(ad.impressionToken)
    }

    /// The ad's player stopped, or started again, without a tap: a call, an
    /// alarm or Siri interrupted the session, the route went away (headphones
    /// pulled), or the lock screen or a headset sent play. An `AVPlayer` does
    /// not start again by itself after an interruption, so left alone the
    /// picture freezes while the break reads as playing — and with no skip to
    /// press, the listener's music stays held behind it. Showing the pause lets
    /// a tap resume it, and `adInterruptionEnded` resumes it when iOS says it
    /// may. Judged on the player as it is now, not as the callback saw it: a
    /// stale ".paused" queued behind a play must not undo it.
    private func adPlayerStateChanged(generation: Int) {
        guard generation == breakGeneration, isAdBreak, let player = adPlayer else { return }
        switch player.timeControlStatus {
        case .paused:
            // A finished item pauses its player on the way to `endAdBreak`;
            // that is the end of the ad, not a pause to show.
            pauseState.playerStopped(itemFinished: hasPlayedToItsEnd(player))
        case .playing, .waitingToPlayAtSpecifiedRate:
            // Only a pause the system made is the system's to take back; one the
            // listener made stays until they undo it.
            pauseState.playerStarted()
        @unknown default:
            break
        }
    }

    private func hasPlayedToItsEnd(_ player: AVPlayer) -> Bool {
        guard let item = player.currentItem else { return false }
        let duration = item.duration.seconds
        return duration.isFinite && duration > 0 && item.currentTime().seconds >= duration - 0.25
    }

    /// The engine has set the audio session up again after an interruption. The
    /// ad's player is not the engine's, so only this starts it — and only when
    /// it was the interruption that stopped it, not the listener.
    private func adInterruptionEnded(shouldResume: Bool) {
        guard isAdBreak, pauseState.interruptionEnded(shouldResume: shouldResume) else { return }
        adPlayer?.play()
    }

    /// `_onAdBreakSkipped` (`bloc.dart:2512`).
    func skip() {
        guard isAdBreak, canSkip else { return }
        endAdBreak()
    }

    /// `_onAdBreakPauseToggled` (`bloc.dart:2532`) — the wall-clock skip
    /// countdown (`adSkipUnlocksAt`) is untouched by pausing, same as Dart:
    /// an ad paused past its unlock time is still skippable the instant the
    /// listener returns to it.
    func togglePause() {
        guard isAdBreak else { return }
        if pauseState.listenerToggled() {
            adPlayer?.pause()
        } else {
            adPlayer?.play()
        }
    }

    /// `_endAdBreak` (`bloc.dart:2574`), including the companion-banner handoff.
    private func endAdBreak() {
        // Said twice (a failed item whose watchdog also fires, a skip racing the
        // end of the item), a second end would lift a hold the next break may
        // already have taken and start the music under it.
        guard isAdBreak else { return }
        let ended = currentAd
        stopAdPlayback()
        // Only an ad that was shown has anything to leave behind on screen.
        let linger = ended.map(progress.leavesCompanion) ?? false
        companionAd = linger ? ended : nil
        showCompanionBanner = linger
        isAdBreak = false
        currentAd = nil
        adPosition = 0
        adTotalDuration = 0
        adSkipUnlocksAt = nil
        progress = AdBreakProgress()
        pauseState = AdPauseState()
        // Whatever is current — the song the break interrupted, or the one the
        // listener queued during it — starts now, ad finished or skipped alike.
        engine.isPlaybackHeld = false
        engine.resume()
    }

    private func stopAdPlayback() {
        breakGeneration += 1
        statusObservation?.invalidate()
        statusObservation = nil
        sizeObservation?.invalidate()
        sizeObservation = nil
        playerStateObservation?.invalidate()
        playerStateObservation = nil
        startupWatchdog?.cancel()
        startupWatchdog = nil
        if let timeObserverToken {
            adPlayer?.removeTimeObserver(timeObserverToken)
        }
        timeObserverToken = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        adPlayer?.pause()
        adPlayer = nil
    }

    /// `openAdAction` (`lib/ads/ad_action.dart`). An in-app destination
    /// (`subscription`, or a `ShareableType` action carrying an `item`) opens
    /// exactly like a shared link to that same content, reusing
    /// `DeepLinkService.openShareable` — that method's own doc comment
    /// already names itself as "`ad_action.dart`'s entry point for an
    /// in-app-destination ad CTA". Only an in-app open tracks a client-side
    /// click, matching Dart exactly: a `clickUrl` fallback's own signed
    /// redirect already records the click server-side, so tracking it again
    /// here would double-count it.
    ///
    /// Scope cut vs. Dart: `openCustomTab` (an in-app browser tab) isn't
    /// ported — this codebase has no such precedent anywhere (`SettingsView`,
    /// `ShareSheetView`, `SubscriptionPlansView` all call
    /// `UIApplication.shared.open`/`openURL` directly, no `canOpenURL` guard
    /// per `ShareSheetView`'s own comment), so the `clickUrl` fallback below
    /// follows that existing convention instead of introducing a new one.
    func openAction(coordinator: AppNavigationCoordinator) {
        guard let ad = currentAd else { return }
        openAction(for: ad, coordinator: coordinator)
    }

    /// `openAdAction(ad)` for any ad, not just the break's — the companion
    /// banner, the strip and the card open an ad that is no longer (or never
    /// was) `currentAd`.
    func openAction(for ad: AdCreative, coordinator: AppNavigationCoordinator) {
        openAdAction(ad, coordinator: coordinator, adsRepository: adsRepository)
    }
}
