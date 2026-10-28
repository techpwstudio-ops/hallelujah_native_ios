import AVFoundation
import Foundation
import Testing
@testable import Hallelujah

/// `AdPacingController` — what an ad break does with the music, the ad's player
/// and the server, from the ask at a song boundary to the music coming back.
///
/// The playback engine is a fake that writes down what it is told. The ad's own
/// player is real: an `AVPlayer` opening a silent WAV generated for the test, so
/// the item's real status, pause and end are what drive the break. No picture is
/// decoded here — a reel's shape is covered by the rules in `AdBreakStateTests`,
/// and in this file only by its absence (a "reel" that has sound and no picture,
/// which the startup watchdog gives up on).
@MainActor
struct AdPacingControllerTests {
    init() {
        // `serve` reads the app-wide remote switch; another suite's leftovers
        // must not decide whether the ad at the centre of a test is served.
        RemoteSettings.current = RemoteSettings.defaults()
    }

    private let log = RequestLog()
    private let engine = FakeBreakEngine()

    private func makeController(
        serving: (@Sendable (SentRequest) -> Data?)? = nil,
        startupTimeout: Duration = AdPacingController.defaultStartupTimeout
    ) -> AdPacingController {
        AdPacingController(
            adsRepository: AdsWire.makeRepository(log: log, serving: serving),
            engine: engine,
            startupTimeout: startupTimeout
        )
    }

    private func serveCalls() -> [SentRequest] {
        log.requests("/ads/serve")
    }

    /// The music was held for the whole break and lowered the hold once, and
    /// `resume` ran once: a second end would start music under the next break.
    private func expectMusicGivenBack(sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(engine.heldHistory == [true, false], sourceLocation: sourceLocation)
        #expect(engine.resumeCalls == 1, sourceLocation: sourceLocation)
    }

    // MARK: asking

    @Test func aSongChangeAsksForABreak() async {
        let controller = makeController() // nothing is served

        engine.onSongChanged?(Song.fixture())
        await AdsWire.waitForRequests(2, in: log)

        // A soundtrack first, then the video when the soundtrack has nothing.
        #expect(serveCalls().map { $0.query["placement"] } == ["audio_between_tracks", "reel_between_tracks"])
        #expect(serveCalls().map { $0.query["assetType"] } == ["audio_ad", "reel_video"])
        #expect(!controller.isAdBreak)
    }

    @Test func aNoFillLeavesTheMusicAlone() async {
        let controller = makeController()

        await controller.maybeStartAdBreak()

        #expect(!controller.isAdBreak)
        #expect(controller.currentAd == nil)
        #expect(engine.heldHistory.isEmpty)
        #expect(engine.pauseCalls == 0)
        #expect(engine.resumeCalls == 0)
    }

    @Test func breaksTakeTurnsBetweenTheFormats() async {
        let controller = makeController(serving: servingPictures) // a fill the break cannot play

        await controller.maybeStartAdBreak()
        await controller.maybeStartAdBreak()

        // Each ask names a format and the placement that format lives on, and the
        // format that went first goes second the next time.
        let asked = serveCalls().map { "\($0.query["placement"] ?? "")|\($0.query["assetType"] ?? "")" }
        #expect(asked == [
            "audio_between_tracks|audio_ad", "reel_between_tracks|reel_video",
            "reel_between_tracks|reel_video", "audio_between_tracks|audio_ad",
        ])
        #expect(!controller.isAdBreak)
    }

    @Test func aSongOnRepeatIsNotABoundary() async {
        let controller = makeController(serving: servingPictures)

        engine.isLoopingOneSong = true
        await controller.maybeStartAdBreak()
        #expect(log.all.isEmpty)

        // The ask that was turned away did not use up the soundtrack's turn.
        engine.isLoopingOneSong = false
        await controller.maybeStartAdBreak()
        #expect(serveCalls().first?.query["assetType"] == "audio_ad")
    }

    @Test func aSecondAskWhileOneIsOutIsTurnedAway() async {
        let controller = makeController() // nothing is served: a soundtrack try, then a video try

        async let first: Void = controller.maybeStartAdBreak()
        async let second: Void = controller.maybeStartAdBreak()
        _ = await (first, second)

        #expect(serveCalls().count == 2) // one ask, not two
    }

    @Test func aPictureServedToABreakIsReportedAndNeverStartsOne() async {
        let controller = makeController(serving: servingPictures)

        await controller.maybeStartAdBreak()
        await AdsWire.waitForRequests(4, in: log) // two asks, two reports

        #expect(!controller.isAdBreak)
        #expect(engine.heldHistory.isEmpty)
        let reports = log.requests("/ads/track/not-shown")
        #expect(reports.count == 2)
        #expect(Set(reports.compactMap { $0.body["reason"] }) == ["unplayable_format"])
        #expect(Set(reports.compactMap { $0.body["token"] }) == ["pic-audio_ad", "pic-reel_video"])
    }

    // MARK: starting

    @Test(arguments: [AudioEngine.Status.idle, .paused, .failed("boom")])
    func aBreakNeverStartsOverMusicThatIsNotPlaying(status: AudioEngine.Status) async {
        engine.status = status
        let controller = makeController(serving: serving(audio: audioAd("https://example.com/ad.mp3")))

        await controller.maybeStartAdBreak()
        await AdsWire.waitForRequests(2, in: log) // the ask, and the report that it was not shown

        #expect(!controller.isAdBreak)
        #expect(log.requests("/ads/track/not-shown").map(\.body) == [["token": "tok", "reason": "superseded"]])
        // The music the listener stopped stays stopped: no hold, no pause, and no
        // resume at the end of a break that never began.
        #expect(engine.heldHistory.isEmpty)
        #expect(engine.pauseCalls == 0)
        #expect(engine.resumeCalls == 0)
    }

    @Test(arguments: [AudioEngine.Status.playing, .loading])
    func aBreakStartsOverMusicThatIsPlayingOrAboutTo(status: AudioEngine.Status) async throws {
        let wav = try silentWAV(seconds: 30)
        defer { try? FileManager.default.removeItem(at: wav) }
        engine.status = status
        let controller = makeController(serving: serving(audio: audioAd(wav.absoluteString, extra: ["skipAfterSec": 0])))

        await controller.maybeStartAdBreak()

        #expect(controller.isAdBreak)
        #expect(controller.currentAd?.impressionToken == "tok")
        // Held for the whole break, paused once, resumed only when it ends.
        #expect(engine.heldHistory == [true])
        #expect(engine.pauseCalls == 1)
        #expect(engine.resumeCalls == 0)

        controller.skip()
        expectMusicGivenBack()
    }

    @Test func anAssetUrlThatIsNotAUrlGivesTheMusicBackAtOnce() async {
        let controller = makeController(serving: serving(audio: audioAd("http://[::1")))

        await controller.maybeStartAdBreak()
        await AdsWire.waitForRequests(2, in: log) // the ask, and the report

        // The break opened (the music was paused behind it) and closed in the same turn.
        #expect(!controller.isAdBreak)
        #expect(engine.pauseCalls == 1)
        expectMusicGivenBack()
        #expect(log.requests("/ads/track/not-shown").map(\.body) == [["token": "tok", "reason": "asset_missing"]])
    }

    @Test func noAskIsMadeWhileABreakIsUp() async throws {
        let wav = try silentWAV(seconds: 30)
        defer { try? FileManager.default.removeItem(at: wav) }
        let controller = makeController(serving: serving(audio: audioAd(wav.absoluteString, extra: ["skipAfterSec": 0])))

        await controller.maybeStartAdBreak()
        let asks = serveCalls().count

        await controller.maybeStartAdBreak()

        #expect(serveCalls().count == asks)
        #expect(controller.isAdBreak)
        controller.skip()
    }

    // MARK: counting, skipping, ending

    @Test func anAudioAdCountsOnceItCanPlayAndGivesTheMusicBackWhenSkipped() async throws {
        let wav = try silentWAV(seconds: 30)
        defer { try? FileManager.default.removeItem(at: wav) }
        let controller = makeController(serving: serving(audio: audioAd(wav.absoluteString, extra: ["skipAfterSec": 0])))

        await controller.maybeStartAdBreak()
        // Nothing has loaded yet, so nothing has been seen or heard.
        #expect(!controller.isAdReady)
        #expect(log.requests("/ads/track/impression").isEmpty)

        await AdsWire.waitUntil("the ad can play") { controller.isAdReady }
        await AdsWire.waitUntil("the impression to be sent") { !log.requests("/ads/track/impression").isEmpty }

        controller.skip()

        #expect(!controller.isAdBreak)
        #expect(controller.adPlayer == nil)
        expectMusicGivenBack()
        #expect(log.requests("/ads/track/impression").map(\.body) == [["token": "tok"]])
        #expect(log.requests("/ads/track/not-shown").isEmpty)
    }

    @Test func anAdWithNoSkipTimeCannotBeSkippedAndRunsToItsEnd() async throws {
        let wav = try silentWAV(seconds: 1)
        defer { try? FileManager.default.removeItem(at: wav) }
        let controller = makeController(serving: serving(audio: audioAd(wav.absoluteString))) // no skipAfterSec

        await controller.maybeStartAdBreak()
        #expect(!controller.canSkip)
        controller.skip()
        #expect(controller.isAdBreak) // there is nothing to skip with
        #expect(!controller.dismissIfSkippable())
        #expect(engine.resumeCalls == 0)

        await AdsWire.waitUntil("the ad to finish") { !controller.isAdBreak }

        expectMusicGivenBack()
        #expect(log.requests("/ads/track/impression").map(\.body) == [["token": "tok"]])
    }

    @Test func theSkipLockHoldsUntilItsTimeComes() async throws {
        let wav = try silentWAV(seconds: 30)
        defer { try? FileManager.default.removeItem(at: wav) }
        let controller = makeController(serving: serving(audio: audioAd(wav.absoluteString, extra: ["skipAfterSec": 1])))

        await controller.maybeStartAdBreak()
        #expect(!controller.canSkip)
        controller.skip()
        #expect(controller.isAdBreak)
        #expect(!controller.dismissIfSkippable()) // "Close ad" is no way round the lock

        await AdsWire.waitUntil("the skip lock to open") { controller.canSkip }

        #expect(controller.dismissIfSkippable())
        #expect(!controller.isAdBreak)
        expectMusicGivenBack()
    }

    @Test func theControlsDoNothingWithoutABreak() {
        let controller = makeController()

        controller.skip()
        controller.togglePause()
        controller.reelWasSeen()
        #expect(!controller.dismissIfSkippable())
        engine.onInterruptionEnded?(true)

        #expect(!controller.isAdBreak)
        #expect(!controller.isAdPaused)
        #expect(controller.adPlayer == nil)
        #expect(engine.heldHistory.isEmpty)
        #expect(engine.resumeCalls == 0)
    }

    // MARK: an ad that will not play

    @Test func aSoundtrackThatCannotBeLoadedIsReportedAsNotPreloaded() async {
        let controller = makeController(serving: serving(audio: audioAd(missingFile)))

        await controller.maybeStartAdBreak()
        #expect(controller.isAdBreak) // it began: the music is paused behind it...
        await AdsWire.waitUntil("the break to give up") { !controller.isAdBreak }
        await AdsWire.waitForRequests(2, in: log) // the ask, and the report

        expectMusicGivenBack() // ...and given back when it fails
        #expect(log.requests("/ads/track/not-shown").map(\.body) == [["token": "tok", "reason": "preload_failed"]])
        #expect(log.requests("/ads/track/impression").isEmpty)
    }

    @Test func aVideoThatCannotBeLoadedIsReportedAsAVideoThatWouldNotStart() async {
        let controller = makeController(serving: serving(reel: reelAd(missingFile)))

        await controller.maybeStartAdBreak()
        await AdsWire.waitUntil("the break to give up") { !controller.isAdBreak }
        await AdsWire.waitForRequests(3, in: log) // the soundtrack's no-fill, the video, the report

        expectMusicGivenBack()
        #expect(log.requests("/ads/track/not-shown").map(\.body) == [["token": "tok", "reason": "video_init_failed"]])
        #expect(log.requests("/ads/track/impression").isEmpty)
    }

    @Test func aReelThatNeverReportsAShapeIsGivenUpOnAndNeverCounted() async throws {
        let wav = try silentWAV(seconds: 30) // a sound, but no picture to size
        defer { try? FileManager.default.removeItem(at: wav) }
        let controller = makeController(serving: serving(reel: reelAd(wav.absoluteString)), startupTimeout: .seconds(1))

        await controller.maybeStartAdBreak()
        // Seen, as far as anyone can tell — but a picture that has no shape is
        // not one the break can lay out, so being seen is not enough.
        controller.reelWasSeen()
        await AdsWire.waitUntil("the watchdog to give up") { !controller.isAdBreak }
        await AdsWire.waitForRequests(3, in: log) // the soundtrack's no-fill, the video, the report

        expectMusicGivenBack()
        #expect(controller.adVideoAspectRatio == 0)
        #expect(log.requests("/ads/track/not-shown").map(\.body) == [["token": "tok", "reason": "video_init_failed"]])
        #expect(log.requests("/ads/track/impression").isEmpty)
    }

    // MARK: what stays up afterwards

    @Test func aShownAdThatAskedToLingerLeavesItsCompanionBanner() async throws {
        let wav = try silentWAV(seconds: 30)
        defer { try? FileManager.default.removeItem(at: wav) }
        let controller = makeController(serving: serving(audio: audioAd(wav.absoluteString, extra: [
            "skipAfterSec": 0,
            "lingerAfterDismiss": true,
            "companionImageUrl": "https://example.com/companion.png",
        ])))

        await controller.maybeStartAdBreak()
        await AdsWire.waitUntil("the impression to be sent") { !log.requests("/ads/track/impression").isEmpty }
        controller.skip()

        #expect(!controller.isAdBreak)
        #expect(controller.showCompanionBanner)
        #expect(controller.companionAd?.impressionToken == "tok")
        #expect(controller.isAdUp) // the banner holds the image takeover off as the break did

        controller.dismissCompanion()
        #expect(!controller.showCompanionBanner)
        #expect(controller.companionAd == nil)
        #expect(!controller.isAdUp)
    }

    @Test func anAdThatFailedLeavesNoBannerEvenIfItAskedToLinger() async {
        let controller = makeController(serving: serving(audio: audioAd(missingFile, extra: [
            "lingerAfterDismiss": true,
            "companionImageUrl": "https://example.com/companion.png",
        ])))

        await controller.maybeStartAdBreak()
        await AdsWire.waitUntil("the break to give up") { !controller.isAdBreak }

        #expect(!controller.showCompanionBanner)
        #expect(controller.companionAd == nil)
        #expect(!controller.isAdUp)
    }

    // MARK: pausing

    @Test func aListenersPauseIsTheirsToUndo() async throws {
        let wav = try silentWAV(seconds: 30)
        defer { try? FileManager.default.removeItem(at: wav) }
        let controller = makeController(serving: serving(audio: audioAd(wav.absoluteString, extra: ["skipAfterSec": 0])))
        await controller.maybeStartAdBreak()
        await AdsWire.waitUntil("the ad can play") { controller.isAdReady }

        controller.togglePause()
        #expect(controller.isAdPaused)
        await AdsWire.waitUntil("the player to stop") { controller.adPlayer?.timeControlStatus == .paused }

        // A call that stopped everything else ends; it is not what stopped this.
        engine.onInterruptionEnded?(true)
        #expect(controller.isAdPaused)
        #expect(controller.adPlayer?.timeControlStatus == .paused)

        controller.togglePause()
        #expect(!controller.isAdPaused)

        controller.skip()
        expectMusicGivenBack()
    }

    @Test func anInterruptionsPauseIsUndoneWhenItEnds() async throws {
        let wav = try silentWAV(seconds: 30)
        defer { try? FileManager.default.removeItem(at: wav) }
        let controller = makeController(serving: serving(audio: audioAd(wav.absoluteString, extra: ["skipAfterSec": 0])))
        await controller.maybeStartAdBreak()
        await AdsWire.waitUntil("the ad can play") { controller.isAdReady }

        // What iOS does to a player when a call comes in: it stops, with no tap.
        controller.adPlayer?.pause()
        await AdsWire.waitUntil("the ad to read as paused") { controller.isAdPaused }

        engine.onInterruptionEnded?(true)
        #expect(!controller.isAdPaused)
        await AdsWire.waitUntil("the player to start again") { controller.adPlayer?.timeControlStatus != .paused }

        controller.skip()
        expectMusicGivenBack()
    }

    @Test func anInterruptionsPauseStaysWhenIOSDoesNotAllowResuming() async throws {
        let wav = try silentWAV(seconds: 30)
        defer { try? FileManager.default.removeItem(at: wav) }
        let controller = makeController(serving: serving(audio: audioAd(wav.absoluteString, extra: ["skipAfterSec": 0])))
        await controller.maybeStartAdBreak()
        await AdsWire.waitUntil("the ad can play") { controller.isAdReady }

        controller.adPlayer?.pause()
        await AdsWire.waitUntil("the ad to read as paused") { controller.isAdPaused }

        engine.onInterruptionEnded?(false)
        #expect(controller.isAdPaused)
        #expect(controller.adPlayer?.timeControlStatus == .paused)

        // A tap takes the pause over and starts the ad again.
        controller.togglePause()
        #expect(!controller.isAdPaused)

        controller.skip()
        expectMusicGivenBack()
    }
}

// MARK: - Doubles and helpers

/// The engine as an ad break sees it, writing down every call and every change
/// of the hold.
@MainActor
private final class FakeBreakEngine: AdBreakEngine {
    var status: AudioEngine.Status = .playing
    var currentSong: Song? = Song.fixture()
    var isLoopingOneSong = false
    var isPlaybackHeld = false {
        didSet { heldHistory.append(isPlaybackHeld) }
    }
    var onSongChanged: ((Song) -> Void)?
    var onInterruptionEnded: ((_ shouldResume: Bool) -> Void)?

    private(set) var heldHistory: [Bool] = []
    private(set) var pauseCalls = 0
    private(set) var resumeCalls = 0

    func pause() { pauseCalls += 1 }
    func resume() { resumeCalls += 1 }
}

/// A picture for whatever the break asks for: a fill it cannot play.
private let servingPictures: @Sendable (SentRequest) -> Data? = { request in
    AdsWire.servedBody(
        assetType: "image_square",
        placement: request.query["placement"] ?? "",
        token: "pic-\(request.query["assetType"] ?? "")"
    )
}

/// `audio` for an `audio_ad` ask and `reel` for a `reel_video` ask; a no-fill
/// for a format that has none.
private func serving(audio: Data? = nil, reel: Data? = nil) -> @Sendable (SentRequest) -> Data? {
    { request in request.query["assetType"] == "reel_video" ? reel : audio }
}

private func audioAd(_ assetUrl: String, extra: [String: Any] = [:]) -> Data {
    AdsWire.servedBody(
        assetType: "audio_ad",
        placement: "audio_between_tracks",
        token: "tok",
        assetUrl: assetUrl,
        extra: extra
    )
}

private func reelAd(_ assetUrl: String, extra: [String: Any] = [:]) -> Data {
    AdsWire.servedBody(
        assetType: "reel_video",
        placement: "reel_between_tracks",
        token: "tok",
        assetUrl: assetUrl,
        extra: extra
    )
}

/// A file that is not there, which the player fails to open.
private let missingFile = URL(fileURLWithPath: "/nonexistent/ad.wav").absoluteString

/// A silent mono 8 kHz 16-bit WAV, written to the system temp directory (not the
/// repo) for the ad's player to open. The test removes it.
private func silentWAV(seconds: Double) throws -> URL {
    let sampleRate: UInt32 = 8_000
    let dataSize = UInt32(Double(sampleRate) * seconds) * 2 // 16-bit samples
    var wav = Data()
    func putText(_ text: String) { wav.append(contentsOf: Array(text.utf8)) }
    func put32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
    func put16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }

    putText("RIFF"); put32(36 + dataSize); putText("WAVE")
    putText("fmt "); put32(16); put16(1); put16(1) // PCM, mono
    put32(sampleRate); put32(sampleRate * 2); put16(2); put16(16) // byte rate, block align, bits
    putText("data"); put32(dataSize)
    wav.append(Data(count: Int(dataSize)))

    let url = FileManager.default.temporaryDirectory.appendingPathComponent("silence-\(UUID().uuidString).wav")
    try wav.write(to: url)
    return url
}
