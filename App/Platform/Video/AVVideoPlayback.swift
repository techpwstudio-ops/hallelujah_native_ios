import AVFoundation
import CoreGraphics

/// The real silent video: an `AVPlayer` that cannot be heard and that the audio engine knows nothing
/// about.
///
/// It is silent twice over (`isMuted` and `volume`) and never touches `AVAudioSession`: the audio
/// engine owns the session, and this player only draws. Every call is a no-op once `teardown()` has
/// run.
@MainActor
final class AVVideoPlayback: VideoPlayback {
    /// What the surface draws.
    let player: AVPlayer

    /// The key the audio engine already hands `AVURLAsset` for its own headers. It is in no SDK header
    /// (the symbol is exported all the same), so it is spelled here the way the engine spells it.
    private static let headerFieldsKey = "AVURLAssetHTTPHeaderFieldsKey"
    /// Seconds of video kept buffered ahead of the playhead.
    static let forwardBufferSeconds: TimeInterval = 10

    private let item: AVPlayerItem
    /// Jumps asked for that have not reported back. A count, because a newer jump cancels an older one
    /// and both report back. Readable so a test can see it; nothing else sets it.
    private(set) var seeksInFlight = 0
    /// Where the newest of them is going.
    private var inFlightTargetMs: Int?
    private var isTornDown = false

    init(url: URL, headers: [String: String]) {
        let options: [String: Any]? = headers.isEmpty ? nil : [Self.headerFieldsKey: headers]
        let item = AVPlayerItem(asset: AVURLAsset(url: url, options: options))
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.volume = 0
        player.actionAtItemEnd = .pause
        // Start drawing as soon as there is a frame, rather than waiting to buffer enough to play
        // through without a stall. The video only decorates the audio and the sync loop catches a
        // stall up, so a fast first frame is worth more than a smooth first second.
        player.automaticallyWaitsToMinimizeStalling = false
        // Keep only a short run ahead of the playhead. The default lets AVPlayer read far ahead,
        // which is data and battery spent on frames the listener may switch away from.
        item.preferredForwardBufferDuration = Self.forwardBufferSeconds
        // A decoration for the audio, never a video to hand to an AirPlay screen.
        player.allowsExternalPlayback = false
        self.item = item
        self.player = player
    }

    // MARK: VideoPlayback

    var isReady: Bool {
        !isTornDown && item.status == .readyToPlay
            && item.presentationSize.width > 0 && item.presentationSize.height > 0
    }

    var hasFailed: Bool {
        !isTornDown && (item.status == .failed || player.status == .failed)
    }

    var positionMs: Int { isTornDown ? 0 : Self.milliseconds(player.currentTime()) }

    var durationMs: Int { isTornDown ? 0 : Self.milliseconds(item.duration) }

    /// `rate` is what was asked for, and stays so while the player waits for data; `isBuffering` tells
    /// those two apart.
    var isPlaying: Bool { !isTornDown && player.rate != 0 }

    var isBuffering: Bool {
        !isTornDown && (seeksInFlight > 0 || player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
    }

    var videoSize: CGSize { isTornDown ? .zero : item.presentationSize }

    func seek(toMs ms: Int) {
        guard !isTornDown else { return }
        let target = max(0, ms)
        // `currentTime()` keeps reporting the old position until a jump lands, so a paused scrub
        // that is slow to land looks, every period, like a video still waiting to be moved. Asking
        // again for the same time would cancel the jump under way and start it over.
        if seeksInFlight > 0, inFlightTargetMs == target { return }
        seeksInFlight += 1
        inFlightTargetMs = target
        // Zero tolerance: the default lets the player land on a keyframe seconds away.
        player.seek(
            to: CMTime(value: CMTimeValue(target), timescale: 1_000),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            Task { @MainActor in self?.seekReported() }
        }
    }

    func play() {
        guard !isTornDown else { return }
        player.play()
    }

    func pause() {
        guard !isTornDown else { return }
        player.pause()
    }

    func teardown() {
        guard !isTornDown else { return }
        isTornDown = true
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    // MARK: Private

    private func seekReported() {
        seeksInFlight = max(0, seeksInFlight - 1)
        if seeksInFlight == 0 { inFlightTargetMs = nil }
    }

    /// Zero for a time that is not a number yet (an item that has not loaded reports an indefinite
    /// duration).
    private static func milliseconds(_ time: CMTime) -> Int {
        guard time.isNumeric else { return 0 }
        let seconds = time.seconds
        return seconds.isFinite ? max(0, Int((seconds * 1_000).rounded())) : 0
    }
}
