import Foundation
import Testing
@testable import Hallelujah

struct ReferralAttributionStoreTests {
    @Test func emptyStoreHasNoSnapshot() {
        #expect(ReferralAttributionStore().snapshot == nil)
    }

    @Test func keepsFirstLinkAsInitialAndLastAsLatest() throws {
        let store = ReferralAttributionStore()
        store.record(try #require(URL(string: "https://example.com/a")))
        store.record(try #require(URL(string: "https://example.com/b")))
        #expect(store.snapshot == ReferAttribution(initial: "https://example.com/a", latest: "https://example.com/b"))
    }

    @Test func encodesOnlyPresentKeys() throws {
        let data = try JSONEncoder().encode(ReferAttribution(initial: "x", latest: nil))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(object == ["initial": "x"])
    }
}
