import Foundation
import Network
import UIKit

/// T38 — ports `AnalyticsTrackingDataUtils` (`lib/utils/analytics_tracking_data_utils.dart`):
/// the `device` object attached to every `/analytics/track` upload.
///
/// Built once, matching Dart's own `init()` being called exactly once per
/// app launch (`flash.dart:86`), not the payload doc's "Updated live" claim
/// for `network_type`/`streamable_variant` — `setNetworkType` (the only
/// writer of either field) has no second call site anywhere in the Dart
/// source, so Dart itself never refreshes these after the first snapshot
/// either; the doc's prose is aspirational, not what ships.
struct PlaybackAnalyticsDeviceInfo: Encodable, Sendable {
    let appName: String?
    let packageName: String?
    let appVersion: String?
    let buildNumber: String?
    let platform: String
    let deviceModel: String
    let deviceBrand: String
    let deviceName: String?
    let deviceManufacturer: String?
    let osVersion: String
    let sdkInt: Int?
    let isPhysicalDevice: Bool
    let deviceType: String
    /// Server-assigned at auth time (`session.dart:122-146`) and only ever
    /// read back for this payload — no native auth flow persists it yet.
    /// `AuthOTPDTOs.swift`/`SocialAuthDTOs.swift` both flag `deviceId` as
    /// "no native consumer yet" when T20-24 deliberately left it unmodeled.
    /// Left `nil` here rather than minting a local UUID the backend never
    /// registered — `ANALYTICS_PAYLOAD.md` documents this field as
    /// String/null for exactly this "not available" case.
    let deviceID: String?
    let locale: String
    let language: String
    let timezone: String
    let timezoneOffset: Int
    let deviceTime: String
    let networkType: String
    let networkSpeed: Double?
    let streamableVariant: String?

    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case packageName = "package_name"
        case appVersion = "app_version"
        case buildNumber = "build_number"
        case platform
        case deviceModel = "device_model"
        case deviceBrand = "device_brand"
        case deviceName = "device_name"
        case deviceManufacturer = "device_manufacturer"
        case osVersion = "os_version"
        case sdkInt = "sdk_int"
        case isPhysicalDevice = "is_physical_device"
        case deviceType = "device_type"
        case deviceID = "device_id"
        case locale, language, timezone
        case timezoneOffset = "timezone_offset"
        case deviceTime = "device_time"
        case networkType = "network_type"
        case networkSpeed = "network_speed"
        case streamableVariant = "streamable_variant"
    }

    @MainActor
    static func current() async -> PlaybackAnalyticsDeviceInfo {
        let bundle = Bundle.main
        let info = bundle.infoDictionary ?? [:]
        let device = UIDevice.current

        var systemInfo = utsname()
        uname(&systemInfo)
        let modelIdentifier = withUnsafePointer(to: &systemInfo.machine) { pointer -> String in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }

        let locale = Locale.current.identifier
        let language = locale.split(separator: "_").first.map(String.init) ?? locale

        let timeZone = TimeZone.current
        let deviceTimeFormatter = DateFormatter()
        deviceTimeFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        deviceTimeFormatter.timeZone = timeZone

        let network = await currentNetworkSnapshot()

        return PlaybackAnalyticsDeviceInfo(
            appName: info["CFBundleName"] as? String,
            packageName: bundle.bundleIdentifier,
            appVersion: info["CFBundleShortVersionString"] as? String,
            buildNumber: info["CFBundleVersion"] as? String,
            platform: "ios",
            deviceModel: modelIdentifier,
            deviceBrand: "Apple",
            deviceName: device.name,
            deviceManufacturer: nil,
            osVersion: device.systemVersion,
            sdkInt: nil,
            isPhysicalDevice: !isSimulator,
            deviceType: device.userInterfaceIdiom == .pad ? "tablet" : "mobile",
            // `getTrackData()['device_id']` — the server-assigned id stored at
            // sign-in (`DeviceIdentityStore`), nil before the first one.
            deviceID: DeviceIdentityStore.shared.deviceID,
            locale: locale,
            language: language,
            timezone: timeZone.abbreviation() ?? timeZone.identifier,
            timezoneOffset: timeZone.secondsFromGMT() / 60,
            deviceTime: deviceTimeFormatter.string(from: Date()),
            networkType: network.type,
            networkSpeed: nil,
            streamableVariant: network.variant
        )
    }

    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    /// One-shot `NWPathMonitor` read, matching Dart's own single
    /// `checkConnectivity()` call in `_collectNetworkInfo()` — a second,
    /// continuously-running monitor alongside `NWPathReachabilityMonitor`
    /// (T19) isn't warranted for a value neither Dart nor this port ever
    /// refreshes after launch (see this type's doc comment).
    ///
    /// `streamable_variant` follows the *actual* Dart branches
    /// (`streamableVariant(result)`, `analytics_tracking_data_utils.dart:129-136`
    /// — wifi/ethernet="high", mobile="standard", none="low"), not the
    /// payload doc's stale "derived from a speed test" description; there is
    /// no speed test anywhere in the Dart source, which is also why
    /// `network_speed` is always `nil` here as it is there.
    private static func currentNetworkSnapshot() async -> (type: String, variant: String) {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "analytics.device-info.network-probe")
            let didResume = LockedFlag()
            monitor.pathUpdateHandler = { path in
                guard didResume.setTrueIfFalse() else { return }
                monitor.cancel()

                let result: (type: String, variant: String)
                if path.status == .satisfied {
                    if path.usesInterfaceType(.wifi) {
                        result = ("wifi", "high")
                    } else if path.usesInterfaceType(.wiredEthernet) {
                        result = ("ethernet", "high")
                    } else if path.usesInterfaceType(.cellular) {
                        result = ("mobile", "standard")
                    } else {
                        result = ("unknown", "standard")
                    }
                } else {
                    result = ("none", "low")
                }
                continuation.resume(returning: result)
            }
            monitor.start(queue: queue)
        }
    }
}

/// `NWPathMonitor.pathUpdateHandler` can fire more than once before
/// `cancel()` takes effect; this guards the continuation against a double
/// `resume(returning:)`, which would trap.
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func setTrueIfFalse() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !value else { return false }
        value = true
        return true
    }
}
