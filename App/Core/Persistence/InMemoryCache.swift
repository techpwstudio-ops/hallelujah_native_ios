import Foundation

/// A bounded in-memory cache over `NSCache` — evicted automatically under
/// memory pressure, plus a hard `countLimit` as a backstop. No consumer yet
/// (T13 media components / T27+ content repositories create one concretely
/// per use, e.g. `InMemoryCache<String, Song>`); this is the shared utility.
final class InMemoryCache<Key: Hashable, Value>: @unchecked Sendable {
    private final class Box {
        let value: Value
        init(_ value: Value) { self.value = value }
    }

    private final class KeyWrapper: NSObject {
        let key: Key
        init(_ key: Key) { self.key = key }

        override func isEqual(_ object: Any?) -> Bool {
            (object as? KeyWrapper)?.key == key
        }

        override var hash: Int { key.hashValue }
    }

    private let storage = NSCache<KeyWrapper, Box>()

    init(countLimit: Int = 200) {
        storage.countLimit = countLimit
    }

    func value(forKey key: Key) -> Value? {
        storage.object(forKey: KeyWrapper(key))?.value
    }

    func set(_ value: Value, forKey key: Key) {
        storage.setObject(Box(value), forKey: KeyWrapper(key))
    }

    func removeValue(forKey key: Key) {
        storage.removeObject(forKey: KeyWrapper(key))
    }

    func removeAll() {
        storage.removeAllObjects()
    }
}
