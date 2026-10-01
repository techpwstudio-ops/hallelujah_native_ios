import Foundation

/// The Wi-Fi/cellular/etc. distinction `ReachabilityMonitoring` deliberately
/// doesn't carry (it's online/offline only). Ports the `ConnectivityResult`
/// input to `streamableVariant` (`lib/utils/analytics_tracking_data_utils.dart:129-136`),
/// which T31's audio-quality network cap needs and nothing before it did.
enum ConnectionType: Sendable {
    case wifi
    case ethernet
    case cellular
    case other
    case none
}

protocol ConnectivityTypeProviding: Sendable {
    /// `nil` until the first path update arrives — callers should treat that
    /// the same way Dart treats a not-yet-collected `streamable_variant`
    /// (`selectBestVariant`'s `networkVariant == null` branch): no network
    /// cap yet, not a `.none`/worst-case cap.
    var currentConnectionType: ConnectionType? { get async }
}
