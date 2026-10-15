import Foundation
import Security

/// Where the server-assigned device id is persisted.
protocol DeviceIDPersisting: Sendable {
    func load() -> String?
    func save(_ deviceID: String?)
}

/// Keychain-backed persistence, the native counterpart of
/// `StorageService.setStringSecurely('deviceId', ...)` /
/// `getStringSecurely('deviceId')` (`lib/services/storage_service.dart`).
/// Like Dart's wrapper, every Keychain failure degrades to "no value" — a
/// locked device at launch must never crash or block a request.
struct KeychainDeviceIDPersistence: DeviceIDPersisting {
    private let service: String
    private let account = "deviceId"

    init(service: String = (Bundle.main.bundleIdentifier ?? "com.hallelujah.user") + ".device") {
        self.service = service
    }

    func load() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ deviceID: String?) {
        SecItemDelete(baseQuery() as CFDictionary)
        guard let deviceID, !deviceID.isEmpty else { return }
        var attributes = baseQuery()
        attributes[kSecValueData as String] = Data(deviceID.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// The `device_id` the server hands back on every session-creating response
/// (`/auth/otp/verify`, `/auth/oauth/verify`, `/auth/token/refresh` —
/// `createSession(deviceId:)`, `lib/utils/session.dart`).
///
/// Dart stores it once and then echoes it as the `device-id` request header
/// (`DioApi.buildHeaders`), in the FCM token registration body, in the
/// topic-sync body, in the logout audit entry and in the analytics `device`
/// object. `createSession` only overwrites it when the response carries a
/// non-null value, and sign-out never clears it (`StorageService.clear()`
/// wipes the Hive box, not secure storage) — both are reproduced here.
///
/// Read synchronously on every request, so the value is cached in memory
/// after the first Keychain read.
final class DeviceIdentityStore: @unchecked Sendable {
    static let shared = DeviceIdentityStore()

    private let persistence: any DeviceIDPersisting
    private let lock = NSLock()
    private var cached: String?
    private var didLoad = false

    init(persistence: any DeviceIDPersisting = KeychainDeviceIDPersistence()) {
        self.persistence = persistence
    }

    /// `nil` until the first sign-in has completed.
    var deviceID: String? {
        lock.lock()
        defer { lock.unlock() }
        if !didLoad {
            cached = persistence.load()
            didLoad = true
        }
        return cached
    }

    /// Records the id from a session response. A nil/empty id leaves the
    /// stored one untouched (`if (deviceId != null)` in `createSession`).
    func update(_ newDeviceID: String?) {
        guard let newDeviceID, !newDeviceID.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard cached != newDeviceID || !didLoad else { return }
        cached = newDeviceID
        didLoad = true
        persistence.save(newDeviceID)
    }
}
