import Foundation

/// Where a Firebase App Check token comes from. Kept as a protocol so
/// `Core/Networking` doesn't import Firebase (`FirebaseAppCheckTokenSource`
/// in `Core/Firebase` is the real one).
protocol AppCheckTokenSource: Sendable {
    func currentToken() async -> String?
}

/// `DioApi._getAppCheckToken` (`lib/services/DioService.dart`): Firebase
/// tokens live about an hour, so one is reused for 45 minutes and then
/// re-fetched. A failed fetch keeps serving the previous token (Dart only
/// overwrites the cache on success) and an empty string is sent when there
/// has never been one.
final class AppCheckTokenCache: @unchecked Sendable {
    /// `_kAppCheckTtl`.
    static let timeToLive: TimeInterval = 45 * 60

    private let lock = NSLock()
    private var source: (any AppCheckTokenSource)?
    private var token: String?
    private var cachedAt: Date?

    init(source: (any AppCheckTokenSource)? = nil) {
        self.source = source
    }

    func install(_ source: any AppCheckTokenSource) {
        lock.lock()
        defer { lock.unlock() }
        self.source = source
    }

    func currentToken(now: Date = Date()) async -> String? {
        let (activeSource, fresh) = snapshot(now: now)
        if let fresh { return fresh }
        guard let activeSource else { return storedToken() }

        if let fetched = await activeSource.currentToken(), !fetched.isEmpty {
            lock.lock()
            token = fetched
            cachedAt = now
            lock.unlock()
            return fetched
        }
        return storedToken()
    }

    /// `DioApi.logout()` — the next request fetches a fresh token.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        token = nil
        cachedAt = nil
    }

    private func snapshot(now: Date) -> (source: (any AppCheckTokenSource)?, fresh: String?) {
        lock.lock()
        defer { lock.unlock() }
        if let token, let cachedAt, now < cachedAt.addingTimeInterval(Self.timeToLive) {
            return (source, token)
        }
        return (source, nil)
    }

    private func storedToken() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return token
    }
}

/// The device/app facts `buildHeaders` reads from
/// `AnalyticsTrackingDataUtils.getTrackData()`.
struct DeviceHeaderInfo: Sendable, Equatable {
    var model: String
    var appVersion: String
    var buildNumber: String
    var os: String

    /// `device_model` is `utsname.machine` (e.g. `iPhone15,2`), same as the
    /// analytics payload; `app_version`/`build_number` are
    /// `CFBundleShortVersionString`/`CFBundleVersion` (`package_info_plus`).
    static let current: DeviceHeaderInfo = {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) { pointer -> String in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        let info = Bundle.main.infoDictionary ?? [:]
        return DeviceHeaderInfo(
            model: machine,
            appVersion: info["CFBundleShortVersionString"] as? String ?? "",
            buildNumber: info["CFBundleVersion"] as? String ?? "",
            // Hardcoded literal, not a per-platform switch — this target
            // only ships iOS (see `HTTPClient`'s history for why the
            // backend needs it: `req.headers["os"]` picks the store).
            os: "ios"
        )
    }()
}

/// `DioApi.buildHeaders` (`lib/services/DioService.dart`): the per-request
/// headers every call carries on top of `Authorization`/`secure` —
/// `app-check-token`, `device-id`, `device-model`, `os`, `app-version`,
/// `build-number`.
///
/// A shared instance (`RequestHeaderProvider.shared`) because every
/// `HTTPClient` — there are many, built all over `AppComposition` — needs the
/// same App Check cache and device id without each call site threading them
/// through. `FirebaseBootstrap.configure()` installs the App Check source once
/// Firebase exists.
final class RequestHeaderProvider: Sendable {
    static let shared = RequestHeaderProvider()

    private let deviceIdentity: DeviceIdentityStore
    private let appCheckCache: AppCheckTokenCache
    private let deviceInfo: DeviceHeaderInfo

    init(
        deviceIdentity: DeviceIdentityStore = .shared,
        appCheckCache: AppCheckTokenCache = AppCheckTokenCache(),
        deviceInfo: DeviceHeaderInfo = .current
    ) {
        self.deviceIdentity = deviceIdentity
        self.appCheckCache = appCheckCache
        self.deviceInfo = deviceInfo
    }

    func installAppCheckSource(_ source: any AppCheckTokenSource) {
        appCheckCache.install(source)
    }

    /// Sign-out: the next request fetches a fresh App Check token.
    func reset() {
        appCheckCache.reset()
    }

    func headers() async -> [String: String] {
        [
            "app-check-token": await appCheckCache.currentToken() ?? "",
            "device-id": deviceIdentity.deviceID ?? "",
            "device-model": deviceInfo.model,
            "os": deviceInfo.os,
            "app-version": deviceInfo.appVersion,
            "build-number": deviceInfo.buildNumber,
        ]
    }
}
