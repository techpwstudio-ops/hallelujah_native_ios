import Foundation
import Testing
@testable import GHallelujah

struct CompanyAdTests {
    private func json(_ extra: [String: Any] = [:]) -> [String: Any] {
        var base: [String: Any] = [
            "adId": "ad1", "placement": "home_banner", "assetType": "image_wide_16_9", "impressionToken": "tok",
        ]
        for (k, v) in extra { base[k] = v }
        return base
    }

    @Test func aCompanyAdWithoutACampaignStillParses() throws {
        let ad = try #require(AdCreative.fromJSON(json(["kind": "company"])))
        #expect(ad.isCompany)
        #expect(ad.campaignId == nil)
        #expect(ad.campaignKey == "company:ad1")
    }

    @Test func aPaidAdKeysOnItsCampaign() throws {
        let ad = try #require(AdCreative.fromJSON(json(["campaignId": "camp9"])))
        #expect(!ad.isCompany)
        #expect(ad.campaignKey == "camp9")
    }

    @Test func screenKeysMapToTabsAndUnknownOnesDoNot() {
        #expect(AdScreenTab.tab(for: "home") == .home)
        #expect(AdScreenTab.tab(for: "search") == .search)
        #expect(AdScreenTab.tab(for: "emet") == .aiAssistant)
        #expect(AdScreenTab.tab(for: "library") == .library)
        #expect(AdScreenTab.tab(for: "bible") == .read)
        #expect(AdScreenTab.tab(for: "settings") == nil)
        #expect(AdScreenTab.tab(for: 3) == nil)
        #expect(AdScreenTab.tab(for: nil) == nil)
    }

    @Test func deepLinkNeedsAnHttpShareLinkOfTwoSegments() {
        #expect(adDeepLinkURL("https://hallelujah.app/share/abc123") != nil)
        #expect(adDeepLinkURL(" http://x.com/share/abc ") != nil)
        #expect(adDeepLinkURL("https://hallelujah.app/share") == nil)
        #expect(adDeepLinkURL("https://hallelujah.app/a/b/c") == nil)
        #expect(adDeepLinkURL("ftp://x.com/share/abc") == nil)
        #expect(adDeepLinkURL(["not": "a string"]) == nil)
        #expect(adDeepLinkURL(nil) == nil)
    }

    @Test func actionItemIsKeptAsStringOrObject() throws {
        let screen = try #require(AdCreative.fromJSON(json(["action": ["type": "screen", "item": "bible"]])))
        #expect(screen.action?.itemString == "bible")
        #expect(screen.action?.itemObject == nil)

        let song = try #require(AdCreative.fromJSON(json(["action": ["type": "song", "item": ["id": "s1"]]])))
        #expect(song.action?.itemObject?["id"] as? String == "s1")
    }
}
