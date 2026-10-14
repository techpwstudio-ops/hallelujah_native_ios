import Foundation
import Testing
@testable import GHallelujah

/// The test double every store test leans on has to behave like the real
/// `KeyValueStoring`, so it gets its own contract tests.
struct InMemoryKeyValueStoreTests {
    @Test func stringsBoolsAndDataRoundTrip() {
        let store = InMemoryKeyValueStore()
        store.setString("v", forKey: "s")
        store.setBool(true, forKey: "b")
        store.setData(Data([1, 2]), forKey: "d")
        #expect(store.string(forKey: "s") == "v")
        #expect(store.bool(forKey: "b"))
        #expect(store.data(forKey: "d") == Data([1, 2]))
    }

    @Test func missingKeysReadAsEmpty() {
        let store = InMemoryKeyValueStore()
        #expect(store.string(forKey: "x") == nil)
        #expect(!store.bool(forKey: "x"))
        #expect(store.data(forKey: "x") == nil)
    }

    @Test func removeValueClearsTheKey() {
        let store = InMemoryKeyValueStore()
        store.setString("v", forKey: "k")
        store.removeValue(forKey: "k")
        #expect(store.string(forKey: "k") == nil)
    }
}
