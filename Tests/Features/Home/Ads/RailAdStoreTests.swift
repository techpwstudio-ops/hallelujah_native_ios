import Foundation
import Testing
@testable import Hallelujah

@MainActor
struct RailAdStoreTests {
    private func creative(_ id: String, campaign: String? = nil, token: String? = nil, company: Bool = false) -> AdCreative {
        var json: [String: Any] = [
            "adId": id,
            "placement": "image_square",
            "assetType": "image_square",
            "assetUrl": "https://example.com/\(id).png",
            "impressionToken": token ?? "t-\(id)",
        ]
        // A company promo has no campaign, so `campaignKey` falls back to `company:<adId>`.
        if company { json["kind"] = "company" } else { json["campaignId"] = campaign ?? "c-\(id)" }
        return AdCreative.fromJSON(json)!
    }

    private final class Box {
        var queue: [AdCreative?]
        var served = 0
        var now = Date(timeIntervalSince1970: 1_000)
        var learned: Int?
        init(_ queue: [AdCreative?]) { self.queue = queue }
    }

    private func store(_ box: Box, prepare: @escaping (AdCreative) async -> Bool = { _ in true }) -> RailAdStore {
        RailAdStore(
            serve: {
                box.served += 1
                return box.queue.isEmpty ? nil : box.queue.removeFirst()
            },
            learnedInterval: { box.learned },
            prepare: prepare,
            now: { box.now }
        )
    }

    @Test func intervalDefaultsToFourUntilServerReportsOne() {
        let box = Box([])
        #expect(store(box).interval == 4)
        box.learned = 6
        #expect(store(box).interval == 6)
        box.learned = 0
        #expect(store(box).interval == 4)
    }

    @Test func intervalIsFixedForTheFeedSessionUntilReset() {
        let box = Box([])
        let s = store(box)
        #expect(s.interval == 4)
        box.learned = 7
        #expect(s.interval == 4)
        s.reset()
        #expect(s.interval == 7)
    }

    @Test func layoutForNilRailCarriesNoAds() {
        let layout = store(Box([])).layoutFor(nil, 20)
        #expect(!layout.hasAds)
    }

    @Test func loadFillsTheSlotOnce() async {
        let box = Box([creative("a")])
        let s = store(box)
        await s.load("r#0")
        await s.load("r#0")
        #expect(s.adFor("r#0")?.adId == "a")
        #expect(box.served == 1)
    }

    @Test func noFillSettlesToNothing() async {
        let s = store(Box([nil]))
        await s.load("r#0")
        #expect(s.adFor("r#0") == nil)
    }

    @Test func artworkThatWillNotLoadMakesNoAd() async {
        let s = store(Box([creative("a")]), prepare: { _ in false })
        await s.load("r#0")
        #expect(s.adFor("r#0") == nil)
    }

    @Test func oneCampaignPerPage() async {
        let box = Box([creative("a", campaign: "same"), creative("b", campaign: "same")])
        let s = store(box)
        await s.load("r#0")
        await s.load("r#1")
        #expect(s.adFor("r#0") != nil)
        #expect(s.adFor("r#1") == nil)
    }

    @Test func companyAdsAreKeyedApartFromCampaigns() {
        #expect(creative("x", company: true).campaignKey == "company:x")
        #expect(creative("x", campaign: "camp").campaignKey == "camp")
    }

    @Test func impressionIsClaimedExactlyOnce() async {
        let ad = creative("a")
        let s = store(Box([ad]))
        await s.load("r#0")
        #expect(s.claimImpression("r#0", ad))
        #expect(!s.claimImpression("r#0", ad))
    }

    @Test func impressionForAnotherCreativeIsRefused() async {
        let s = store(Box([creative("a")]))
        await s.load("r#0")
        #expect(!s.claimImpression("r#0", creative("other")))
    }

    @Test func unseenAdIsAskedAgainOnlyOnceStale() async {
        let box = Box([creative("a"), creative("b")])
        let s = store(box)
        await s.load("r#0")
        box.now.addTimeInterval(RailAdStore.staleAfter - 1)
        #expect(!s.needsLoad("r#0"))
        box.now.addTimeInterval(2)
        #expect(s.needsLoad("r#0"))
        await s.load("r#0")
        #expect(s.adFor("r#0")?.adId == "b")
    }

    @Test func seenAdIsNeverReshuffled() async {
        let ad = creative("a")
        let box = Box([ad, creative("b")])
        let s = store(box)
        await s.load("r#0")
        _ = s.claimImpression("r#0", ad)
        box.now.addTimeInterval(RailAdStore.staleAfter * 3)
        #expect(!s.needsLoad("r#0"))
    }

    @Test func dismissedSlotStaysCollapsed() async {
        let s = store(Box([creative("a")]))
        await s.load("r#0")
        s.dismiss("r#0")
        #expect(s.adFor("r#0") == nil)
        #expect(!s.needsLoad("r#0"))
    }

    @Test func resetForgetsEverythingAndBumpsGeneration() async {
        let s = store(Box([creative("a")]))
        await s.load("r#0")
        let before = s.generation
        s.reset()
        #expect(s.adFor("r#0") == nil)
        #expect(s.needsLoad("r#0"))
        #expect(s.generation == before + 1)
    }
}
