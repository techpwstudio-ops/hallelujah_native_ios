import Foundation
import Observation

/// Mirrors `SettingsService`'s getters and their exact fallback values
/// (`lib/services/settings_service.dart`) — `freeTrialPeriod` (45),
/// `adsEnabled` (true), `showSubscription` (false), `cdnUrl` (an
/// environment-specific CloudFront URL).
///
/// Populated by `AppDataSync` (the port of `DataService.getInitData()`), which
/// calls `RemoteSettings.apply(settings:)` with the `settings` map of every
/// `/dashboard/init` response. On the dev branch `SettingsService.init()` IS
/// called from `main()` — `RemoteSettings.restore()` is its counterpart,
/// called from `GHallelujahApp.init()` — so the last-known values are live
/// from the first frame and the hardcoded fallbacks only apply on a first
/// launch with no cached payload.
///
/// Getters that are hardcoded constants in Dart regardless of remote data
/// (`showVideoAds`, `minSecondsPlayedForAds`, `nativeAdsSegment`, …) aren't
/// modeled here — they aren't settings, they're Ads-milestone constants, and
/// belong wherever that milestone actually needs them.
struct RemoteSettings: Sendable, Equatable {
    var freeTrialPeriod: Int
    var adsEnabled: Bool
    var showSubscription: Bool
    /// A full URL string (Dart's `cdnUrl`), not a bare host — see
    /// `ArtworkURLResolver`, the one consumer, for why.
    var cdnUrl: String

    /// `configuration.cdnHost` is already the same per-environment
    /// CloudFront host Dart's own fallback ternary resolves to (see the
    /// T15 Production.xcconfig fix note) — reusing it here keeps that host
    /// defined in exactly one place instead of re-hardcoding it.
    static func defaults(configuration: AppConfiguration = .current) -> RemoteSettings {
        RemoteSettings(
            freeTrialPeriod: 45,
            adsEnabled: true,
            showSubscription: false,
            cdnUrl: "https://\(configuration.cdnHost)"
        )
    }
}

extension RemoteSettings {
    /// Applies the `settings` map of a `/dashboard/init` response the way
    /// `SettingsService`'s getters read it (`settings_service.dart`):
    /// `adsEnabled` / `showSubscription` are parsed with `bool.tryParse
    /// ('${data[key]}')` — so a JSON bool or the strings "true"/"false" count
    /// and anything else falls back to the default — and `cdnUrl` is used when
    /// present, else the per-environment default. `freeTrialPeriod` has no
    /// remote source in Dart (`SettingsService` has no such getter) and keeps
    /// its default.
    static func resolved(from settings: [String: Any], configuration: AppConfiguration = .current) -> RemoteSettings {
        var result = RemoteSettings.defaults(configuration: configuration)
        result.adsEnabled = parseBool(settings["adsEnabled"]) ?? true
        result.showSubscription = parseBool(settings["showSubscription"]) ?? false
        if let cdnUrl = settings["cdnUrl"] as? String, !cdnUrl.isEmpty {
            result.cdnUrl = cdnUrl
        }
        return result
    }

    /// `bool.tryParse('$value')`: exactly `true` / `false` (case-sensitive).
    static func parseBool(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool: return bool
        case let text as String:
            if text == "true" { return true }
            if text == "false" { return false }
            return nil
        default: return nil
        }
    }

    private static let persistenceKey = "remoteSettings"

    /// `SettingsService.set(settings)`: replaces the whole map (a key the
    /// server stopped sending reverts to its default) and persists it so the
    /// next cold start already has it.
    @MainActor
    static func apply(settings: [String: Any], store: any KeyValueStoring = UserDefaultsKeyValueStore()) {
        current = resolved(from: settings)
        if let data = try? JSONSerialization.data(withJSONObject: settings) {
            store.setData(data, forKey: persistenceKey)
        }
    }

    /// `SettingsService.init()` (called from `main()`): restore the last
    /// known map before the first frame, so a launch with no signal does not
    /// run on defaults (which hides the premium button).
    @MainActor
    static func restore(store: any KeyValueStoring = UserDefaultsKeyValueStore()) {
        guard let data = store.data(forKey: persistenceKey),
              let settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        current = resolved(from: settings)
    }

    nonisolated(unsafe) private static var storage = RemoteSettings.defaults()

    /// The running app's one shared settings value, following
    /// `DependencyContainer.current`'s precedent for "the thing the app
    /// actually reads from" — settings are read from call sites all over
    /// the app (same as Dart's `SettingsService.instance`), not resolved
    /// per-use through DI.
    ///
    /// Reading it from a SwiftUI `body` registers an observation on
    /// `RemoteSettingsRevision`, so a view that gates on `showSubscription`
    /// re-renders when `/dashboard/init` lands — what Dart's
    /// `settingsProvider` / `revision` notifier is for.
    static var current: RemoteSettings {
        get {
            _ = RemoteSettingsRevision.shared.value
            return storage
        }
        set {
            storage = newValue
            RemoteSettingsRevision.shared.value += 1
        }
    }
}

/// `SettingsService.revision` — bumped every time the settings change.
@Observable
final class RemoteSettingsRevision: @unchecked Sendable {
    static let shared = RemoteSettingsRevision()
    var value = 0
    private init() {}
}
