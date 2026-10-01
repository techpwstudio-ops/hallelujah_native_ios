import AVFoundation
import Foundation
import UIKit

/// Ports the player ad-break slice of `PlayerBloc` (`lib/blocs/player/bloc.dart`):
/// `_maybeStartAdBreak`/`_tracksSinceLastAdBreak`/`_pacingEveryN` for cadence,
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
/// Also NOT ported: `_preloadAdCreative`'s separate preload-then-switch
/// phase. It exists in Dart purely to mask `just_audio`/`video_player`'s
/// cold-start latency on a throwaway player instance; `AVPlayer(url:)`
/// already starts buffering immediately on construction, so there's no
/// equivalent latency to hide behind a second phase.
///
/// Also NOT ported: `lingerAfterDismiss`'s companion-banner handoff
/// (`_endAdBreak`'s `companionAd`/`showCompanionBanner` branch) — there is no
/// native host surface for a lingering banner outside the full player (the
/// mini player / dashboard banner spot Dart uses doesn't exist in this
/// rewrite), so a break always ends cleanly with nothing left behind.
@MainActor
@Observable
final class AdPacingController {
    private let adsRepository: AdsRepository
    private let engine: AudioEngine

    private(set) var isAdBreak = false
    private(set) var currentAd: AdCreative?
    private(set) var adPosition: TimeInterval = 0
    private(set) var adTotalDuration: TimeInterval = 0
    private(set) var isAdPaused = false
    private(set) var adSkipUnlocksAt: Date?

    /// Not `private` — `AdBreakView` reads this directly to feed AVKit's
    /// `VideoPlayer(player:)` for a `reel_video` creative's visible surface;
    /// everything else about ad playback stays internal to this controller.
    private(set) var adPlayer: AVPlayer?
    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?

    /// `_tracksSinceLastAdBreak`/`_pacingEveryN` (`bloc.dart:238-247`). Not
    /// reset on a no-fill (mirrors Dart exactly — see `maybeStartAdBreak`
    /// below): once the threshold is reached, every subsequent track retries
    /// until one actually fills.
    private var tracksSinceLastAdBreak = 0
    private var pacingEveryN: Int?
    private var adBreakFetchInFlight = false

    private static let placement = "audio_between_tracks"
    private static let previewAssetTypes = ["audio_ad", "reel_video"]
    /// Dart's own local allowlist (`_kShareableActionTypes`, `ad_action.dart`)
    /// — deliberately narrower than the full `ShareableType` enum: `app` and
    /// `bibleVerse` are excluded there on purpose, so this mirrors the exact
    /// set rather than reusing `ShareableType.allCases`.
    private static let shareableActionTypes: Set<String> = [
        "song", "creator", "playlist", "userPlaylist", "companyPlaylist", "verseOfDay",
    ]
    private var previewAssetTypeIndex = 0

    init(adsRepository: AdsRepository, engine: AudioEngine) {
        self.adsRepository = adsRepository
        self.engine = engine
        engine.onSongChanged = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.maybeStartAdBreak() }
        }
    }

    var canSkip: Bool {
        guard let adSkipUnlocksAt else { return false }
        return Date() >= adSkipUnlocksAt
    }

    /// `_maybeStartAdBreak` (`bloc.dart:973`). `force` skips the pacing count
    /// only — the serve, no-fill handling and in-flight guard are identical
    /// either way, matching Dart's own doc comment on that parameter.
    func maybeStartAdBreak(force: Bool = false) async {
        guard !isAdBreak, !adBreakFetchInFlight else { return }

        if !force {
            tracksSinceLastAdBreak += 1
            let threshold = pacingEveryN ?? 6
            guard tracksSinceLastAdBreak >= threshold else { return }
        }

        let preview = force && AppConfiguration.current.featureFlags.adsPreviewMode
        var assetType: String?
        if preview {
            assetType = Self.previewAssetTypes[previewAssetTypeIndex]
            previewAssetTypeIndex = (previewAssetTypeIndex + 1) % Self.previewAssetTypes.count
        }

        adBreakFetchInFlight = true
        defer { adBreakFetchInFlight = false }

        var ad = await adsRepository.serve(placement: Self.placement, assetType: assetType, ignoreRetryBackoff: preview)

        // A format with nothing booked must not read as "ads are broken" —
        // retry unrestricted so a preview request still shows something.
        if preview, ad?.assetUrl == nil {
            ad = await adsRepository.serve(placement: Self.placement, ignoreRetryBackoff: true)
        }

        // Ports `_maybeStartAdBreak`'s actual guard verbatim. Dart's own
        // comment immediately above that line claims "the break is still
        // valid" when `squareImageUrl` is nil, but the code it's attached to
        // requires BOTH `assetUrl` and `squareImageUrl` to proceed — this
        // ports the code that runs, not the comment that contradicts it.
        guard let ad, ad.assetUrl != nil, ad.squareImageUrl != nil else { return }

        pacingEveryN = ad.adLoad.pacingEveryN ?? pacingEveryN
        tracksSinceLastAdBreak = 0
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

    /// `_onAdBreakStarted` (`bloc.dart:2479`).
    private func startAdBreak(with ad: AdCreative) {
        guard !isAdBreak else { return }
        engine.pause()

        currentAd = ad
        adPosition = 0
        adTotalDuration = TimeInterval(ad.durationSec ?? 0)
        adSkipUnlocksAt = ad.skipAfterSec.map { Date().addingTimeInterval(TimeInterval($0)) }
        isAdPaused = false
        isAdBreak = true

        playAdCreative(ad)
    }

    /// `_playAdCreative` (`bloc.dart:2609`) — see this file's own doc comment
    /// on why one `AVPlayer` covers both formats here.
    private func playAdCreative(_ ad: AdCreative) {
        guard let urlString = ad.assetUrl, let url = URL(string: urlString) else {
            endAdBreak()
            return
        }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        adPlayer = player

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.endAdBreak() }
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

        player.play()
        adsRepository.trackImpression(ad.impressionToken)
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
        isAdPaused.toggle()
        if isAdPaused {
            adPlayer?.pause()
        } else {
            adPlayer?.play()
        }
    }

    /// `_endAdBreak` (`bloc.dart:2574`), minus the companion-banner handoff —
    /// see this file's own doc comment on why.
    private func endAdBreak() {
        stopAdPlayback()
        isAdBreak = false
        currentAd = nil
        adPosition = 0
        adTotalDuration = 0
        adSkipUnlocksAt = nil
        isAdPaused = false
        engine.resume()
    }

    private func stopAdPlayback() {
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

        if let action = ad.action {
            if action.type == "subscription" {
                adsRepository.trackClick(ad.impressionToken)
                coordinator.push(.subscriptionPlans)
                return
            }
            if let item = action.item, Self.shareableActionTypes.contains(action.type) {
                adsRepository.trackClick(ad.impressionToken)
                DeepLinkService.shared.openShareable(shareableType: action.type, item: item, coordinator: coordinator)
                return
            }
        }

        if let clickUrl = ad.clickUrl, let url = URL(string: clickUrl) {
            UIApplication.shared.open(url)
        }
    }
}
