import Observation

/// `Loader.instance` (`lib/services/loading_service.dart`): the app-wide
/// blocking spinner — a non-dismissible dialog with a centred spinner over a
/// dimmed barrier — raised around short service-level requests that have no
/// screen of their own to show progress on (opening a shared link, opening a
/// push destination, creating a share link), and around a store purchase or
/// restore, which must not be interrupted by navigating away.
///
/// `show()` while already showing is a no-op, and `hide()` only acts when
/// something is showing, exactly like Dart's `loading` flag. Rendered by
/// `AppInfrastructureHost`.
@MainActor
@Observable
final class GlobalLoader {
    static let shared = GlobalLoader()

    private(set) var isLoading = false

    private init() {}

    func show() {
        guard !isLoading else { return }
        isLoading = true
    }

    func hide() {
        guard isLoading else { return }
        isLoading = false
    }
}
