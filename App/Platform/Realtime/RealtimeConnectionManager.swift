import Foundation
import SocketIO

/// Ports `WebSocketService` (`lib/services/websocket.dart`) — connect with
/// the existing long-lived access token as a query param, not the separate
/// short-lived `generateSocketToken`/`/socket/token` REST flow (confirmed
/// against `websocket.dart` itself: `IO.io(url, OptionBuilder()
/// .setQuery({'token': token})...)`; `/socket/token` only exists for the
/// creator/admin channels — `src/routes/creator/user.routes.js`,
/// `src/routes/admin/admin.routes.js` — never for this listener app).
///
/// `@MainActor @Observable`, same shape as `AudioEngine`/`QueueController`:
/// a captured shared instance meant to live for the app's whole lifetime,
/// wrapping a non-`Sendable` third-party client (`SocketManager`/
/// `SocketIOClient`, `socket.io-client-swift`) the same way `AudioEngine`
/// wraps `AVQueuePlayer`.
@MainActor
@Observable
final class RealtimeConnectionManager {
    enum Status: Equatable, Sendable {
        case disconnected
        case connecting
        case connected
    }

    private(set) var status: Status = .disconnected

    private let configuration: AppConfiguration
    private let authProvider: any AuthTokenProviding
    private let dispatcher: RealtimeEventDispatcher
    private let logger = AppLogger(category: .realtime)

    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var connectedToken: String?

    init(configuration: AppConfiguration, authProvider: any AuthTokenProviding, dispatcher: RealtimeEventDispatcher) {
        self.configuration = configuration
        self.authProvider = authProvider
        self.dispatcher = dispatcher
    }

    /// Call once a session exists: after a successful login and again at
    /// cold start when a stored session is still valid — Dart calls
    /// `WebSocketService.instance.init(token)` from both spots
    /// (`session.dart`'s post-login save around line 150, and its
    /// app-launch bootstrap around line 580). Neither call site is this
    /// manager's own file — see T67's integration report for the exact
    /// hook this needs in `AppComposition.swift`/wherever session start is
    /// observed, both protected files this task doesn't edit directly.
    ///
    /// Idempotent: already-connecting or already-connected-with-the-same-token
    /// is a no-op, matching Dart's own `_isConnecting`/`_isConnected && _token
    /// == token` guards.
    func connect() async {
        guard status != .connecting else { return }
        guard let token = await authProvider.currentAccessToken(), !token.isEmpty else {
            logger.warning("realtime connect skipped — no access token")
            return
        }
        if status == .connected, connectedToken == token { return }

        disconnect()
        status = .connecting
        connectedToken = token

        // Dart: `.setTransports(['websocket'])` (no polling fallback) +
        // `.setQuery({'token': token})` + `.enableReconnection()`. Reconnect
        // backoff is the library's own (`.reconnectAttempts`/`.reconnectWait`)
        // rather than porting Dart's manual `_attemptReconnect` exponential
        // backoff loop — `socket.io-client-swift` already does this natively,
        // and duplicating it here would fight the library's own retry timer.
        let manager = SocketManager(
            socketURL: configuration.socketBaseURL,
            config: [
                .forceWebsockets(true),
                .connectParams(["token": token]),
                .reconnects(true),
                .reconnectAttempts(5),
                .reconnectWait(2),
                .log(configuration.environment == .development)
            ]
        )
        self.manager = manager
        let socket = manager.defaultSocket
        self.socket = socket

        socket.on(clientEvent: .connect) { [self] _, _ in
            Task { @MainActor in self.status = .connected }
        }
        socket.on(clientEvent: .disconnect) { [self] _, _ in
            Task { @MainActor in self.status = .disconnected }
        }
        socket.on(clientEvent: .error) { [self] data, _ in
            Task { @MainActor in self.logger.warning("realtime socket error: \(String(describing: data))") }
        }
        // Dispatches EVERY incoming event by name, matching Dart's
        // `_socket!.onAny((event, data) { _dispatchEvent(event, data); })` —
        // the server never asks the client to `socket.on()` each event name
        // individually, it just emits whatever a listener's rooms receive.
        socket.onAny { [self] event in
            let name = event.event
            let items = event.items
            Task { @MainActor in self.dispatcher.dispatch(name: name, items: items) }
        }

        socket.connect()
    }

    /// Call on logout (`Session`'s `onLogout` closure, `AppComposition.swift`
    /// — protected, see T67's integration report) and on the same
    /// root-teardown Dart disconnects on (`launch_app.dart`'s `dispose()`).
    func disconnect() {
        socket?.removeAllHandlers()
        socket?.disconnect()
        socket = nil
        manager = nil
        connectedToken = nil
        status = .disconnected
    }
}
