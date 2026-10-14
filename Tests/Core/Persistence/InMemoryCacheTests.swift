import Testing
@testable import GHallelujah

struct InMemoryCacheTests {
    @Test func storesAndReturnsValuesByKey() {
        let cache = InMemoryCache<String, Int>()
        cache.set(1, forKey: "a")
        cache.set(2, forKey: "b")
        #expect(cache.value(forKey: "a") == 1)
        #expect(cache.value(forKey: "b") == 2)
        #expect(cache.value(forKey: "missing") == nil)
    }

    @Test func overwritingReplacesTheValue() {
        let cache = InMemoryCache<String, Int>()
        cache.set(1, forKey: "a")
        cache.set(9, forKey: "a")
        #expect(cache.value(forKey: "a") == 9)
    }

    @Test func removeValueAndRemoveAll() {
        let cache = InMemoryCache<String, Int>()
        cache.set(1, forKey: "a")
        cache.set(2, forKey: "b")
        cache.removeValue(forKey: "a")
        #expect(cache.value(forKey: "a") == nil)
        #expect(cache.value(forKey: "b") == 2)
        cache.removeAll()
        #expect(cache.value(forKey: "b") == nil)
    }

    @Test func nonStringKeysWork() {
        let cache = InMemoryCache<Int, String>()
        cache.set("one", forKey: 1)
        #expect(cache.value(forKey: 1) == "one")
    }
}
