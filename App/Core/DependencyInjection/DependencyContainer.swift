import Foundation

/// A minimal type-keyed factory registry. `resolve()` calls the registered
/// factory fresh every time — a registration that should behave as a shared
/// instance registers a closure that captures one, rather than the container
/// caching values itself.
final class DependencyContainer: @unchecked Sendable {
    private var factories: [ObjectIdentifier: () -> Any] = [:]
    private let lock = NSLock()

    func register<Value>(_ type: Value.Type = Value.self, factory: @escaping () -> Value) {
        lock.lock()
        defer { lock.unlock() }
        factories[ObjectIdentifier(type)] = factory
    }

    func resolve<Value>(_ type: Value.Type = Value.self) -> Value {
        lock.lock()
        let factory = factories[ObjectIdentifier(type)]
        lock.unlock()

        guard let factory, let value = factory() as? Value else {
            preconditionFailure("No registration for \(Value.self)")
        }
        return value
    }
}

extension DependencyContainer {
    /// The container the running app resolves against. `AppComposition`
    /// installs the real one at launch; previews and tests install their own.
    nonisolated(unsafe) static var current = DependencyContainer()
}
