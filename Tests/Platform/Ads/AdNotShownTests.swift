import Foundation
import Testing
@testable import Hallelujah

/// `AdsRepository.reportNotShown` — the half of the serve/impression story only
/// the app can tell.
///
/// The reports are fire-and-forget. A test waits for what it expects to arrive
/// (`AdsWire.waitForRequests`, which fails the test if it never does). That
/// something was NOT sent can only be shown by giving it room to arrive and then
/// seeing that it did not (`allowStrays`): a slow machine makes such a test pass
/// more easily, never fail, so where a request is expected after the one that
/// must be absent, the test waits for that one first.
@MainActor
struct AdNotShownTests {
    init() {
        // `serve` reads the app-wide remote switch; another suite's leftovers
        // must not decide whether the ad at the centre of a test is served.
        RemoteSettings.current = RemoteSettings.defaults()
    }

    /// Room for a request that was wrongly sent to arrive before the test looks.
    private func allowStrays() async {
        try? await Task.sleep(for: .milliseconds(100))
    }

    @Test func postsTheTokenAndTheReasonToTheNotShownEndpoint() async {
        let log = RequestLog()
        let repository = AdsWire.makeRepository(log: log)

        repository.reportNotShown(makePlayerAdCreative(token: "tok-1"), .videoInitFailed)
        await AdsWire.waitForRequests(1, in: log)

        #expect(log.all.count == 1)
        #expect(log.all.first?.path.hasSuffix("/ads/track/not-shown") == true)
        #expect(log.all.first?.body == ["token": "tok-1", "reason": "video_init_failed"])
    }

    @Test func aTokenIsReportedOnceWhateverTheReason() async {
        let log = RequestLog()
        let repository = AdsWire.makeRepository(log: log)
        let ad = makePlayerAdCreative(token: "tok-2")

        repository.reportNotShown(ad, .preloadFailed)
        repository.reportNotShown(ad, .superseded)
        repository.reportNotShown(makePlayerAdCreative(token: "tok-3"), .superseded)
        await AdsWire.waitForRequests(2, in: log)
        await allowStrays() // a wrongly sent third

        #expect(log.all.count == 2)
        #expect(Set(log.all.compactMap { $0.body["token"] }) == ["tok-2", "tok-3"])
        #expect(log.all.first { $0.body["token"] == "tok-2" }?.body["reason"] == "preload_failed")
    }

    /// A company ad's token is not a paid one, so the server would drop the
    /// report; the app does not send it (as `submitFeedback` and `react` don't).
    @Test func aCompanyAdIsNeverReported() async {
        let log = RequestLog()
        let repository = AdsWire.makeRepository(log: log)
        let company = makePlayerAdCreative(token: "tok-co", extra: ["kind": "company"])
        #expect(company.isCompany)

        // The paid report after it is the thing to wait for: anything the
        // company one sent was queued before it.
        repository.reportNotShown(company, .assetMissing)
        repository.reportNotShown(makePlayerAdCreative(token: "tok-paid"), .assetMissing)
        await AdsWire.waitForRequests(1, in: log)
        await allowStrays() // a wrongly sent company report

        #expect(log.all.compactMap { $0.body["token"] } == ["tok-paid"])
    }

    @Test func aCampaignMutedAMomentAgoIsDroppedAtServeAndReported() async throws {
        let log = RequestLog()
        let body = AdsWire.servedBody(
            assetType: "reel_video",
            placement: "reel_between_tracks",
            token: "tok-m",
            assetUrl: "https://example.com/m.mp4"
        )
        let repository = AdsWire.makeRepository(log: log, serving: { _ in body })

        // Not muted yet: the ad comes through, and nothing is said about it.
        let first = try #require(await repository.serve(placement: "reel_between_tracks", assetType: "reel_video"))
        #expect(log.requests("/ads/track/not-shown").isEmpty)

        // The ask names the format and the placement it lives on.
        let ask = try #require(log.requests("/ads/serve").first)
        #expect(ask.query["placement"] == "reel_between_tracks")
        #expect(ask.query["assetType"] == "reel_video")

        // "Not interested", and the server's cached candidates still hold the campaign.
        repository.submitFeedback(ad: first, kind: .notInterested)
        let second = await repository.serve(placement: "reel_between_tracks", assetType: "reel_video")
        #expect(second == nil)

        await AdsWire.waitForRequests(4, in: log) // two serves, the feedback, the report
        #expect(log.requests("/ads/track/not-shown").map(\.body) == [["token": "tok-m", "reason": "muted_campaign"]])
    }

    /// The server keeps no check between the two stories, so the app tells one.
    @Test func aCreativeAlreadyCountedAsShownIsNotAlsoReportedAsNotShown() async {
        let log = RequestLog()
        let repository = AdsWire.makeRepository(log: log)
        let ad = makePlayerAdCreative(token: "tok-shown")

        repository.trackImpressionOnce(ad.impressionToken)
        repository.reportNotShown(ad, .videoInitFailed)
        await AdsWire.waitForRequests(1, in: log)
        await allowStrays() // a wrongly sent report

        #expect(log.requests("/ads/track/impression").map(\.body) == [["token": "tok-shown"]])
        #expect(log.requests("/ads/track/not-shown").isEmpty)
    }

    @Test func aCreativeReportedAsNotShownIsNotThenCountedAsShown() async {
        let log = RequestLog()
        let repository = AdsWire.makeRepository(log: log)
        let ad = makePlayerAdCreative(token: "tok-unseen")

        repository.reportNotShown(ad, .preloadFailed)
        repository.trackImpressionOnce(ad.impressionToken)
        await AdsWire.waitForRequests(1, in: log)
        await allowStrays() // a wrongly sent impression

        #expect(log.requests("/ads/track/not-shown").map(\.body) == [["token": "tok-unseen", "reason": "preload_failed"]])
        #expect(log.requests("/ads/track/impression").isEmpty)
    }

    @Test func anImpressionIsCountedOncePerToken() async {
        let log = RequestLog()
        let repository = AdsWire.makeRepository(log: log)

        repository.trackImpressionOnce("tok-a")
        repository.trackImpressionOnce("tok-a")
        repository.trackImpressionOnce("tok-b")
        await AdsWire.waitForRequests(2, in: log)
        await allowStrays() // a wrongly sent third

        let counted = log.requests("/ads/track/impression").compactMap { $0.body["token"] }
        #expect(counted.count == 2)
        #expect(Set(counted) == ["tok-a", "tok-b"])
    }

    @Test func anEmptyTokenIsNeverReported() async {
        let log = RequestLog()
        let repository = AdsWire.makeRepository(log: log)

        repository.reportNotShown(makePlayerAdCreative(token: ""), .assetMissing)
        await allowStrays()

        #expect(log.all.isEmpty)
    }

    @Test func theReasonsAreTheServersClosedList() {
        #expect(Set(AdNotShownReason.allCases.map(\.rawValue)) == [
            "unplayable_format", "asset_missing", "preload_failed", "video_init_failed",
            "muted_campaign", "superseded", "expired_before_show",
        ])
    }
}
