import Foundation

/// Mirrors `SettingsService`'s getters and their exact fallback values
/// (`lib/services/settings_service.dart`) — `freeTrialPeriod` (45),
/// `adsEnabled` (true), `showSubscription` (false), `cdnUrl` (an
/// environment-specific CloudFront URL).
///
/// **Not** a live remote fetch. `SettingsService.data` starts as an empty
/// map and is only ever populated by `DataService._updateSettings()`, which
/// only runs inside `getInitData()` — itself triggered by session creation
/// (`lib/utils/session.dart:513`) or a websocket reconnect
/// (`lib/services/websocket.dart:65`), never by the splash screen.
/// `SettingsService.instance.init()`, the one method that would restore a
/// locally-cached `data` map across cold launches, has zero call sites in
/// the whole Dart app — so on every real cold start, Dart itself is running
/// on these hardcoded fallbacks until login (or a reconnect) first
/// populates `data`. `RemoteSettings.current` reproduces exactly that:
/// T15 seeds it with these defaults and nothing more: whichever later
/// milestone ports `getInitData()` (most likely alongside T20-24's session
/// creation) is what should start mutating `RemoteSettings.current` from a
/// real response.
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
    /// The running app's one shared settings value, following
    /// `DependencyContainer.current`'s precedent for "the thing the app
    /// actually reads from" — settings are read from call sites all over
    /// the app (same as Dart's `SettingsService.instance`), not resolved
    /// per-use through DI.
    nonisolated(unsafe) static var current = RemoteSettings.defaults()
}
