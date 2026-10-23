import MediaPlayer
import Observation
import UIKit

/// T32 — feeds `AudioEngine`'s state to `MPNowPlayingInfoCenter` and wires
/// `MPRemoteCommandCenter` (lock screen / Control Center) back into it.
/// Deliberately a separate observer, not folded into `AudioEngine` itself —
/// `AudioEngine`'s own T31 doc comment already scoped it as "exposes
/// status/currentSong/currentPosition/currentItemDuration for... T32's Now
/// Playing wiring to read," anticipating exactly this split.
///
/// Ports the OS-facing half of `MyAudioHandler`
/// (`lib/services/audio_service.dart`), which itself sits on top of the
/// `audio_service` package rather than calling `MPNowPlayingInfoCenter`/
/// `MPRemoteCommandCenter` directly — so this ports what Dart FEEDS that
/// package (`_buildMediaItem`, the remote-command overrides,
/// `_broadcastState`'s update cadence), not any Dart call site 1:1.
@MainActor
final class NowPlayingCoordinator {
    /// Matches `_buildMediaItem`'s own `variant: 'md'` (`audio_service.dart:630-636`)
    /// — deliberately not `.lg` despite that variant's own doc comment naming
    /// it for "Full player / hero artwork"; Dart's real choice for lock-screen
    /// artwork is `.md`, matched here rather than the seemingly-more-fitting one.
    private static let artworkVariant = ImageVariant.md
    private static let artworkMaxPixelSize: CGFloat = 300

    private let engine: AudioEngine
    private let queueController: QueueController
    private let tokenProvider: any AuthTokenProviding
    private let proxyHost: String?
    /// The current song's lock-screen artwork, kept so every republish
    /// (each play/pause/loading change) carries it. Rebuilding the info
    /// without it blanked the artwork until the async fetch put it back —
    /// the flicker on every tap in Control Center / the lock screen.
    private var artwork: (songID: String, artwork: MPMediaItemArtwork)?

    init(
        engine: AudioEngine,
        queueController: QueueController,
        tokenProvider: any AuthTokenProviding,
        configuration: AppConfiguration = .current
    ) {
        self.engine = engine
        self.queueController = queueController
        self.tokenProvider = tokenProvider
        proxyHost = configuration.proxyBaseURL.host

        registerRemoteCommands()
        trackEngine()
    }

    // MARK: - Observation

    /// Re-registers itself on every fire — `withObservationTracking`'s
    /// `onChange` closure runs exactly once per registration, the standard
    /// pattern for observing an `@Observable` type outside a SwiftUI view
    /// body. Deliberately reads only `status`/`currentSong`/
    /// `currentItemDuration`, never `currentPosition` — matching
    /// `_broadcastState`'s own explicit anti-pattern warning
    /// (`audio_service.dart:280-288`): iOS animates the lock-screen scrubber
    /// automatically from the last known position + rate, so a position-tick-
    /// driven republish (Dart measured this at "potentially hundreds of
    /// times a minute" in the background) has zero visual benefit and real
    /// CPU/IPC cost. `currentItemDuration` only ever changes once per track
    /// (nil -> a value, then stable), so tracking it doesn't reintroduce that
    /// same problem.
    private func trackEngine() {
        withObservationTracking {
            _ = engine.status
            _ = engine.currentSong
            _ = engine.currentItemDuration
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.publish()
                self?.trackEngine()
            }
        }
    }

    // MARK: - Publishing

    private func publish() {
        guard let song = engine.currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title ?? "",
            MPMediaItemPropertyArtist: Self.artistLine(for: song),
            MPMediaItemPropertyAlbumTitle: Self.albumLine(for: song),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: engine.currentPosition,
            MPNowPlayingInfoPropertyPlaybackRate: engine.status == .playing ? 1.0 : 0.0,
        ]
        let duration = engine.currentItemDuration ?? TimeInterval(song.duration ?? 0)
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let artwork, artwork.songID == song.id {
            info[MPMediaItemPropertyArtwork] = artwork.artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        let publishedSongID = song.id
        Task { [weak self] in
            guard let self, let image = await self.resolveArtworkImage(for: song) else { return }
            guard self.engine.currentSong?.id == publishedSongID else { return }
            let artwork = Self.makeArtwork(image)
            self.artwork = (publishedSongID, artwork)
            var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            updated[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
        }
    }

    /// Built in a nonisolated context: MediaPlayer invokes the request handler
    /// on its own queue, and a closure formed in a main-actor method traps the
    /// runtime isolation check there.
    private nonisolated static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    /// `artUri`/`artHeaders` (`audio_service.dart:638-645`): a proxy URL
    /// needs the same bearer header `AudioSourceResolver`'s
    /// `requiresAuthHeader` case already carries for audio (T31); a direct
    /// CDN URL needs none (`ArtworkImageCache`'s own default path, unchanged
    /// for every pre-T32 caller).
    private func resolveArtworkImage(for song: Song) async -> UIImage? {
        guard let url = ArtworkURLResolver().resolve(
            path: song.image, variant: Self.artworkVariant, allowedVariants: song.imageVariants
        ) else { return nil }

        guard let proxyHost, url.host == proxyHost else {
            return await ArtworkImageCache.shared.image(for: url, maxPixelSize: Self.artworkMaxPixelSize)
        }
        let token = await tokenProvider.validAccessToken() ?? ""
        return await ArtworkImageCache.shared.image(
            for: url, maxPixelSize: Self.artworkMaxPixelSize, headers: ["Authorization": "Bearer \(token)"]
        )
    }

    /// `artistLine`/`artist` (`audio_service.dart:645-653`): primaryArtists +
    /// featuredArtists joined by Dart's own `dotSign` (`" • "`,
    /// `lib/constants/strings.dart:22`), falling back to the creator's name,
    /// falling back to an empty string — never the literal "Unknown", per
    /// Dart's own comment that an empty artist line reads better on the lock
    /// screen than a placeholder when the metadata genuinely isn't available.
    private static func artistLine(for song: Song) -> String {
        let parts = [song.primaryArtists, song.featuredArtists]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let joined = parts.joined(separator: " • ")
        if !joined.isEmpty { return joined }
        if let name = song.creator?.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            return name
        }
        return ""
    }

    /// `album` (`audio_service.dart:655-661`): creator name if present, else
    /// `song.type`, both `.capitalized` — matched exactly, including
    /// capitalizing the creator name itself, since that's what Dart's own
    /// code does uniformly rather than only capitalizing the `song.type`
    /// fallback branch.
    private static func albumLine(for song: Song) -> String {
        if let name = song.creator?.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            return name.capitalized
        }
        return (song.type ?? "").capitalized
    }

    // MARK: - Remote commands

    /// Ports `MyAudioHandler`'s overridden `play`/`pause`/`seek`/
    /// `skipToNext`/`skipToPrevious` (`audio_service.dart:1657-1984,2315-2325`).
    /// No `fastForward`/`rewind`/`setRating` handler exists in Dart either
    /// (confirmed absent, not just unported) — `skipForwardCommand`/
    /// `skipBackwardCommand` stay disabled rather than advertising a control
    /// with no real behavior behind it. `MPRemoteCommandCenter` target
    /// closures aren't guaranteed to run on the main thread, so each one
    /// only synchronously extracts its (`Sendable`) event payload before
    /// hopping onto `@MainActor` — `AudioEngine`'s own isolation requires it.
    private func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.engine.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.engine.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.engine.status == .playing { self.engine.pause() } else { self.engine.resume() }
            }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in await self?.queueController.skipToNext() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                // `skipToPrevious()`'s >3s-restart branch only seeks — it
                // doesn't touch status/currentSong/currentItemDuration, the
                // only properties `trackEngine()` observes, so it wouldn't
                // otherwise trigger a republish. The actual-previous-track
                // branch DOES change `currentSong` and would republish on
                // its own; calling `publish()` unconditionally here is a
                // harmless redundant republish in that case, not a bug.
                await self?.queueController.skipToPrevious()
                self?.publish()
            }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in
                self?.engine.seek(to: position)
                self?.publish()
            }
            return .success
        }
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
    }
}
