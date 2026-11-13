import Foundation
import Observation

/// The silent video players one layer has on screen: the one showing now, and, while the listener's
/// new quality loads, the one opening behind it.
///
/// A quality change used to rebuild the layer, which tore the old player down and showed the cover
/// until the new file was ready. Now the old picture keeps playing in step while the new file opens
/// and catches up with the audio underneath it. Once the new picture is in step it fades in on top,
/// and when the fade is over the old player is released. The listener sees the picture sharpen (or
/// soften), never the cover, as on YouTube.
///
/// It owns no timer and opens no files. The layer opens a player when `needsOpening` says so, hands
/// it to `open(_:)`, and calls `tick(stepMs:)` on its loop, which keeps both players with the audio
/// and makes the swap. That keeps it testable with fake players and fake time.
@MainActor
@Observable
final class PlayerVideoStage<Playback: VideoPlayback> {
    typealias Player = PlayerVideoHandoff<Playback>.Held

    /// What a tick changed that the layer has to act on.
    enum Event {
        /// `player` has taken over the screen; the one before it has been released.
        case switched(Player)
        /// The file the listener wants cannot be played.
        case failed
    }

    /// Where `open(_:)` put a player.
    enum Placement: Equatable {
        /// On screen at once: there was no picture to keep up meanwhile.
        case current
        /// Behind the picture on screen, until it is in step.
        case incoming
    }

    /// The file the listener wants, for the quality they picked.
    private(set) var wanted: URL
    /// The player on screen; `nil` before the first file opens.
    private(set) var current: Player?
    /// The player for `wanted` while it opens behind `current`.
    private(set) var incoming: Player?

    /// How long the new picture has been in step, counted on the loop's time; `nil` while it is not.
    @ObservationIgnored private var incomingShownForMs: Int?
    /// How long the new picture is given to fade in over the old before the old one goes.
    @ObservationIgnored private let fadeMs: Int

    /// `showing` is a player another layer left for this episode, so the first frame draws it.
    init(wanted: URL, showing: Player? = nil, fadeMs: Int = Int(MotionDuration.crossfade * 1_000)) {
        self.wanted = wanted
        self.current = showing
        self.fadeMs = fadeMs
    }

    /// Whether a player has to be opened for `wanted`: neither the picture on screen nor the one
    /// opening behind it plays that file.
    var needsOpening: Bool {
        current?.url != wanted && incoming?.url != wanted
    }

    /// No switch is under way.
    var isSettled: Bool { incoming == nil }

    /// The picture on screen is the right frame. The spinner and the controls over the picture read
    /// this; during a switch the old picture counts, so neither flickers.
    var isPictureShown: Bool { current?.controller.isShown ?? false }

    /// The video has given up: the player on screen failed and nothing is opening to replace it.
    var hasFailed: Bool { incoming == nil && (current?.controller.hasFailed ?? false) }

    /// The listener picked another quality. A file opening for an earlier pick is let go; picking
    /// the quality on screen again cancels the switch.
    func want(_ url: URL) {
        guard url != wanted else { return }
        wanted = url
        if let incoming, incoming.url != url { drop(incoming) }
    }

    /// Shows `player`, the one this episode's layer took over from the handoff. `nil` means nothing
    /// was held: whatever this stage still points at has been released, so it is cleared.
    func show(_ player: Player?) {
        guard current?.controller !== player?.controller else { return }
        current = player
    }

    /// Puts a player just opened for `wanted` on stage. It goes on screen at once when there is no
    /// picture to keep up meanwhile; otherwise it opens behind the one on screen. A player still
    /// opening for an earlier pick is released.
    @discardableResult
    func open(_ player: Player) -> Placement {
        if let incoming { drop(incoming) }
        guard let current, !current.controller.hasFailed else {
            self.current = player
            return .current
        }
        incoming = player
        incomingShownForMs = nil
        return .incoming
    }

    /// Releases `player` if it is the one opening behind the picture, and nothing otherwise. The
    /// player on screen belongs to the handoff and is let go there.
    func drop(_ player: Player) {
        guard let incoming, incoming.controller === player.controller else { return }
        self.incoming = nil
        incomingShownForMs = nil
        incoming.controller.release()
    }

    /// Releases everything. For a layer going out of sight, where nothing is kept.
    func clear() {
        if let incoming { drop(incoming) }
        current?.controller.release()
        current = nil
    }

    /// One look at both players, `stepMs` after the last. Keeps each with the audio and makes the
    /// swap once the new picture has been in step for the length of the fade.
    func tick(stepMs: Int) -> Event? {
        current?.controller.tick(stepMs: stepMs)
        guard let incoming else {
            return current?.controller.hasFailed == true ? .failed : nil
        }
        incoming.controller.tick(stepMs: stepMs)
        if incoming.controller.hasFailed {
            drop(incoming)
            return .failed
        }
        // Counted from the tick it came into step, so the fade it starts then has time to finish.
        incomingShownForMs = incoming.controller.isShown ? incomingShownForMs.map { $0 + stepMs } ?? 0 : nil
        let currentIsBroken = current?.controller.hasFailed ?? true
        guard currentIsBroken || (incomingShownForMs ?? 0) >= fadeMs else { return nil }
        current?.controller.release()
        current = incoming
        self.incoming = nil
        incomingShownForMs = nil
        return .switched(incoming)
    }
}
