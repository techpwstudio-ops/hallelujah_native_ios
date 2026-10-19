import Foundation
@testable import Hallelujah

/// A `KeyValueStoring` that never touches `UserDefaults`, so tests neither
/// leak state into each other nor into the real app's defaults.
final class InMemoryKeyValueStore: KeyValueStoring, @unchecked Sendable {
    private var storage: [String: Any] = [:]
    private let lock = NSLock()

    func string(forKey key: String) -> String? { read(key) }
    func setString(_ value: String?, forKey key: String) { write(value, key) }
    func bool(forKey key: String) -> Bool { read(key) ?? false }
    func setBool(_ value: Bool, forKey key: String) { write(value, key) }
    func data(forKey key: String) -> Data? { read(key) }
    func setData(_ value: Data?, forKey key: String) { write(value, key) }
    func removeValue(forKey key: String) { write(Optional<Int>.none, key) }

    private func read<Value>(_ key: String) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key] as? Value
    }

    private func write(_ value: (some Any)?, _ key: String) {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = value
    }
}
