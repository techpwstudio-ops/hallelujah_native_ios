import Foundation

/// Ports `lib/services/car_integration_notifier.dart`: the single fan-out
/// point for "this changed, tell the car UI" events. Every call site that
/// mutates something a CarPlay screen shows (a play, a favourite toggle, a
/// finished download, a playlist edit) posts exactly one of these; the live
/// `CarPlayController` (if a CarPlay scene is connected) observes and re-fetches
/// whatever is currently visible. With no scene connected the posts are
/// harmless no-ops. Android Auto's half of the Dart class has no iOS analog.
enum CarIntegrationNotifier {
    enum Change: String, Sendable {
        case recentPlayed
        case favourites
        case downloads
        case playlists
        case playlistSongs
    }

    static let didChange = Notification.Name("CarIntegrationNotifier.didChange")
    static let changeKey = "change"
    static let playlistIDKey = "playlistID"

    static func recentPlayed() {
        post(.recentPlayed)
    }

    static func favouritesChanged() {
        post(.favourites)
    }

    static func downloadsChanged() {
        post(.downloads)
    }

    static func playlistsChanged() {
        post(.playlists)
    }

    /// Ignored for a nil/empty id, same as the Dart guard.
    static func playlistSongsChanged(playlistID: String?) {
        guard let playlistID, !playlistID.isEmpty else { return }
        post(.playlistSongs, playlistID: playlistID)
    }

    private static func post(_ change: Change, playlistID: String? = nil) {
        var info: [String: Any] = [changeKey: change.rawValue]
        if let playlistID { info[playlistIDKey] = playlistID }
        NotificationCenter.default.post(name: didChange, object: nil, userInfo: info)
    }

    static func change(from notification: Notification) -> Change? {
        (notification.userInfo?[changeKey] as? String).flatMap(Change.init(rawValue:))
    }

    static func playlistID(from notification: Notification) -> String? {
        notification.userInfo?[playlistIDKey] as? String
    }
}
