import CoreGraphics

/// The silent video player as the controller sees it: seven reads and four commands, and no
/// AVFoundation, so tests drive the controller with a fake.
@MainActor
protocol VideoPlayback: AnyObject {
    /// The item is ready to play and its picture size is known.
    var isReady: Bool { get }
    /// The item or the player has failed for good.
    var hasFailed: Bool { get }
    var positionMs: Int { get }
    /// Zero until known.
    var durationMs: Int { get }
    var isPlaying: Bool { get }
    /// Waiting for data, or for a jump to land.
    var isBuffering: Bool { get }
    var videoSize: CGSize { get }

    /// Fire and watch: returns at once, and a jump in flight counts as buffering until it lands.
    func seek(toMs ms: Int)
    func play()
    func pause()
    /// Stops the player and lets go of everything it holds. Safe to call twice.
    func teardown()
}
