import Foundation
import SocketIO

/// T59 — ports `RealtimeChannel`/`SocketIoRealtimeChannel`
/// (`lib/features/voice/net/realtime_channel.dart`). The uplink to the
/// `/voice` namespace.
///
/// Audio flows one way — up. Nothing that comes back down is audio; the
/// reply arrives as text and is spoken on-device. That asymmetry is why
/// this interface has a `sendAudio` and no receive counterpart.
@MainActor
protocol VoiceRealtimeChannel: AnyObject {
    var onEvent: ((VoiceServerEvent) -> Void)? { get set }
    var onStatusChange: ((VoiceChannelStatus) -> Void)? { get set }
    var currentStatus: VoiceChannelStatus { get }
    var sttLocale: String? { get }
    var ttsLocale: String? { get }
    var droppedFrameCount: Int { get }

    func connect(conversationID: String?, ttsLocale: String?) async
    /// Hands one 3200-byte PCM16LE frame to the uplink. Never blocks and
    /// never throws: capture runs on the audio callback and must not be
    /// made to wait on a congested socket. A frame that cannot be sent is
    /// buffered, and if the buffer is full the OLDEST frame is dropped —
    /// stale audio is worthless to a recogniser, fresh audio is not.
    func sendAudio(_ frame: Data)
    /// Tells the server the user interrupted, and from which sentence.
    /// `seq` is the sentence the device is CURRENTLY speaking — the first
    /// one it has not finished. The server echoes it back as
    /// `v.cancelled{fromSeq}` and the speech queue flushes from there.
    /// Passing nil lets the server fall back to its own last-emitted seq,
    /// which is too high.
    func barge(seq: Int?)
    func cancel(reason: String, seq: Int)
    func sendDeviceTranscript(text: String, language: String?, ms: Int)
    func setLocale(ttsLocale: String, sttLocale: String?)
    func close()
}

/// socket.io-client-swift implementation of `VoiceRealtimeChannel`.
@MainActor
final class SocketIOVoiceChannel: VoiceRealtimeChannel {
    // MARK: Tunables — ported verbatim from `SocketIoRealtimeChannel`.

    /// 50 frames = 5s of audio at 100ms per frame. Deep enough to ride out
    /// a brief stall, shallow enough that what finally gets sent is still
    /// recent.
    private static let maxBufferedFrames = 50
    /// Liveness ping interval.
    private static let markInterval: Duration = .seconds(1)
    /// Unanswered marks before the socket is no longer believed alive.
    /// socket.io keeps reporting "connected" across a dead TCP connection
    /// far longer than a conversation can tolerate, so this runs its own
    /// detector on top.
    private static let maxMissedAcks = 3
    /// How long the outbox must stay in overflow before the user is told
    /// the network is the problem.
    private static let slowLinkWindow: TimeInterval = 2
    /// Rate limit on the `net_slow` report, so a long stall is one message
    /// and not a stream of them.
    private static let slowLinkReportGap: TimeInterval = 5
    /// Attempts on the TOP rung of the ladder before the link is declared
    /// dead. The policy itself never gives up, by design — a conversation
    /// is ended by the user or by a fatal error, not by the backoff
    /// running out of patience. Five attempts at 8s is ~40s of genuine
    /// effort before giving up.
    private static let maxCeilingAttempts = 5

    var onEvent: ((VoiceServerEvent) -> Void)?
    var onStatusChange: ((VoiceChannelStatus) -> Void)?

    private(set) var currentStatus: VoiceChannelStatus = .idle {
        didSet {
            guard currentStatus != oldValue else { return }
            onStatusChange?(currentStatus)
        }
    }
    private(set) var sttLocale: String?
    private(set) var ttsLocale: String?
    private(set) var droppedFrameCount = 0

    private let session: Session
    private let voiceSocketURL: URL
    private let policy = VoiceReconnectPolicy()

    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var reconnectTask: Task<Void, Never>?
    private var markTask: Task<Void, Never>?

    /// Set by `close()`. Suppresses every reconnect path so a deliberate
    /// hangup cannot be undone by a disconnect callback arriving a moment
    /// later.
    private var closedByUs = false
    /// Consecutive failures once the backoff ladder is sitting on its last
    /// rung.
    private var ceilingAttempts = 0
    /// Set when the link is declared dead. Stops the ladder for good.
    private var gaveUp = false

    // Session state carried across reconnects.
    private var conversationID: String?
    /// Handed back in `v.ready` and replayed in the next `v.hello`. This is
    /// what lets the server pick up the same conversation instead of
    /// starting a new one every time the tunnel flaps.
    private var resumeToken: String?

    // Liveness.
    private var markSeq = 0
    private var lastAckSeq = 0

    // Outgoing audio.
    private var outbox: [Data] = []
    private var overflowSince: Date?
    private var lastSlowReport: Date?

    init(session: Session, configuration: AppConfiguration) {
        self.session = session
        voiceSocketURL = configuration.socketBaseURL.appendingPathComponent("voice")
    }

    // MARK: Connect / reconnect

    func connect(conversationID: String?, ttsLocale: String?) async {
        closedByUs = false
        gaveUp = false
        ceilingAttempts = 0
        // A caller-supplied value wins; otherwise keep what a previous
        // connect or setLocale established, so a reconnect does not
        // silently revert locale.
        if let conversationID { self.conversationID = conversationID }
        if let ttsLocale { self.ttsLocale = ttsLocale }

        policy.reset()
        await openSocket()
    }

    private func openSocket() async {
        teardownSocket()

        guard let token = await session.currentAccessToken(), !token.isEmpty else {
            onEvent?(.error(VoiceErrorPayload(code: VoiceErrorCode.unauthenticated, message: String(localized: "Not signed in."), fatal: true)))
            currentStatus = .closed
            return
        }

        currentStatus = policy.attempt == 0 ? .connecting : .reconnecting

        // A dedicated `SocketManager` per attempt gives the voice namespace
        // its own connection instead of sharing T67's default-namespace
        // manager at the same host — mirrors Dart's `enableForceNew()}`.
        // Sharing would mean this channel's disconnect tears down the
        // app's main socket, and its reconnect settings would override
        // this channel's own.
        //
        // Reconnection is disabled on purpose (`.reconnects(false)`):
        // `VoiceReconnectPolicy` drives it, because every reconnect has to
        // replay `v.hello` with the resume token, which socket.io's own
        // built-in retry knows nothing about.
        let manager = SocketManager(socketURL: voiceSocketURL, config: [
            .forceWebsockets(true),
            .connectParams(["token": token]),
            .reconnects(false),
            .log(false),
        ])
        self.manager = manager
        let socket = manager.defaultSocket
        self.socket = socket

        socket.on(clientEvent: .connect) { [weak self] _, _ in
            Task { @MainActor in self?.handleConnected() }
        }
        socket.on(clientEvent: .disconnect) { [weak self] data, _ in
            let reason = (data.first as? String) ?? "unknown"
            Task { @MainActor in self?.handleDropped("disconnect: \(reason)") }
        }
        socket.on(clientEvent: .error) { [weak self] data, _ in
            Task { @MainActor in
                guard let self else { return }
                // socket.io-client-swift does not distinguish a handshake
                // failure from a mid-session error the way Dart's
                // `onConnectError`/`onError` pair does; not yet having
                // reached `.open` on this attempt is the closest available
                // proxy for "this happened during connect".
                let duringHandshake = self.currentStatus != .open
                self.handleDropped("error: \(data)", handshake: duringHandshake)
            }
        }

        for name in VoiceServerEventName.all {
            socket.on(name) { [weak self] items, _ in
                Task { @MainActor in self?.handleServerEvent(name: name, items: items) }
            }
        }

        socket.connect()
    }

    private func handleConnected() {
        guard !closedByUs else { return }

        policy.reset()
        ceilingAttempts = 0
        markSeq = 0
        lastAckSeq = 0
        currentStatus = .open

        let hello = VoiceHelloPayload(conversationId: conversationID, ttsLocale: ttsLocale, resumeToken: resumeToken)
        socket?.emit(VoiceClientEvent.hello, socketPayload(hello))

        startMarkTask()
        flushOutbox()
    }

    /// Any way the link can die: a clean disconnect, a failed handshake, or
    /// this channel's own liveness detector giving up on it.
    private func handleDropped(_ reason: String, handshake: Bool = false) {
        guard !closedByUs, !gaveUp else { return }

        stopMarkTask()

        // A handshake the server actively REJECTED is not a transport
        // problem and will not fix itself: the middleware answers an
        // expired, blacklisted or malformed token with an unauthorized
        // error. Retrying that on a ladder is 40 seconds of the user
        // watching "Reconnecting…" for an answer that has already arrived.
        if handshake, Self.looksUnauthorized(reason) {
            giveUp(code: VoiceErrorCode.unauthenticated, message: String(localized: "Your session has expired. Please sign in again."))
            return
        }

        currentStatus = .reconnecting
        scheduleReconnect()
    }

    private static func looksUnauthorized(_ reason: String) -> Bool {
        let lower = reason.lowercased()
        return lower.contains("unauthorized")
            || lower.contains("unauthenticated")
            || lower.contains("forbidden")
            || lower.contains("invalid token")
            || lower.contains("jwt")
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()

        if policy.atCeiling {
            ceilingAttempts += 1
            if ceilingAttempts > Self.maxCeilingAttempts {
                giveUp(code: VoiceErrorCode.netDown, message: String(localized: "Lost connection. Please check your network and try again."))
                return
            }
        }

        let delay = policy.nextDelay()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            guard !self.closedByUs, !self.gaveUp else { return }
            await self.openSocket()
        }
    }

    /// Ends the session for good with a fatal error the controller can act
    /// on. Deliberately fatal: the alternative is `reconnecting` forever,
    /// microphone open, no error, no exit.
    private func giveUp(code: String, message: String) {
        gaveUp = true
        reconnectTask?.cancel()
        reconnectTask = nil
        stopMarkTask()
        teardownSocket()

        onEvent?(.error(VoiceErrorPayload(code: code, message: message, fatal: true)))
        currentStatus = .closed
    }

    // MARK: Liveness

    private func startMarkTask() {
        stopMarkTask()
        markTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.markInterval)
                guard !Task.isCancelled else { return }
                self?.sendMark()
            }
        }
    }

    private func stopMarkTask() {
        markTask?.cancel()
        markTask = nil
    }

    private func sendMark() {
        guard let socket, socket.status == .connected else { return }

        if markSeq - lastAckSeq >= Self.maxMissedAcks {
            // The socket still claims to be connected but nothing is
            // coming back. Treat it as dead and rebuild it rather than
            // keep talking into a void.
            handleDropped("\(Self.maxMissedAcks) marks unanswered")
            return
        }

        markSeq += 1
        let mark = VoiceMarkPayload(seq: markSeq, tMs: Int(Date().timeIntervalSince1970 * 1000))
        socket.emit(VoiceClientEvent.mark, socketPayload(mark))
    }

    // MARK: Inbound

    private func handleServerEvent(name: String, items: [Any]) {
        guard let event = VoiceServerEventParsing.parse(name: name, items: items) else {
            // Forward compatibility: the server is allowed to grow new
            // events, and an old client must shrug rather than crash the
            // conversation.
            return
        }

        switch event {
        case let .ready(payload):
            resumeToken = payload.resumeToken
            conversationID = payload.conversationId
            sttLocale = payload.sttLocale
            ttsLocale = payload.ttsLocale
        case let .ack(payload):
            // Marks are monotonic; a reordered or duplicated ack must not
            // walk the watermark backwards into a false "socket is dead".
            if payload.seq > lastAckSeq { lastAckSeq = payload.seq }
            // Acks are pure liveness — the controller has no use for them.
            return
        case let .localeChanged(payload):
            sttLocale = payload.sttLocale
            ttsLocale = payload.ttsLocale
        default:
            break
        }

        onEvent?(event)
    }

    // MARK: Outbound audio

    func sendAudio(_ frame: Data) {
        guard !closedByUs else { return }

        outbox.append(frame)
        if outbox.count > Self.maxBufferedFrames {
            outbox.removeFirst()
            droppedFrameCount += 1
            if overflowSince == nil { overflowSince = Date() }
            maybeReportSlowLink()
        }

        flushOutbox()
    }

    private func flushOutbox() {
        guard let socket, socket.status == .connected else { return }

        while !outbox.isEmpty {
            // socket.io serialises `Data` as a binary attachment, so the
            // frame travels as bytes rather than being base64-inflated
            // into JSON.
            socket.emit(VoiceClientEvent.audio, outbox.removeFirst())
        }

        // Drained: whatever backlog there was is over.
        overflowSince = nil
    }

    /// Reports a sustained backlog once per `slowLinkReportGap`. A handful
    /// of dropped frames during a handover is normal and inaudible;
    /// several seconds of them means the recogniser is being fed holes and
    /// the user deserves to know why the answers stopped making sense.
    private func maybeReportSlowLink() {
        guard let since = overflowSince else { return }

        let now = Date()
        guard now.timeIntervalSince(since) >= Self.slowLinkWindow else { return }
        if let last = lastSlowReport, now.timeIntervalSince(last) < Self.slowLinkReportGap { return }

        lastSlowReport = now
        onEvent?(.error(VoiceErrorPayload(
            code: VoiceErrorCode.netSlow,
            message: String(localized: "Network is too slow to send audio — \(droppedFrameCount) frames dropped."),
            fatal: false
        )))
    }

    // MARK: Outbound control

    func barge(seq: Int?) {
        emitToSocket(VoiceClientEvent.barge, socketPayload(VoiceBargePayload(seq: seq)))
    }

    func sendDeviceTranscript(text: String, language: String?, ms: Int) {
        emitToSocket(VoiceClientEvent.sttDevice, socketPayload(VoiceDeviceSttPayload(text: text, language: language, ms: ms)))
    }

    func cancel(reason: String, seq: Int) {
        emitToSocket(VoiceClientEvent.cancel, socketPayload(VoiceCancelPayload(reason: reason, seq: seq)))
    }

    func setLocale(ttsLocale: String, sttLocale: String?) {
        // Remembered as well as sent: if the socket flaps before the
        // server confirms, the next `v.hello` still carries the locale the
        // user chose.
        self.ttsLocale = ttsLocale
        if let sttLocale { self.sttLocale = sttLocale }

        emitToSocket(VoiceClientEvent.localeSet, socketPayload(VoiceLocaleSetPayload(ttsLocale: ttsLocale, sttLocale: sttLocale)))
    }

    private func emitToSocket(_ event: String, _ payload: [String: Any]) {
        guard let socket, socket.status == .connected else { return }
        socket.emit(event, payload)
    }

    // MARK: Shutdown

    func close() {
        closedByUs = true

        reconnectTask?.cancel()
        reconnectTask = nil
        stopMarkTask()

        if let socket, socket.status == .connected {
            socket.emit(VoiceClientEvent.bye, [String: Any]())
        }

        teardownSocket()

        gaveUp = false
        ceilingAttempts = 0
        outbox.removeAll()
        droppedFrameCount = 0
        overflowSince = nil
        lastSlowReport = nil
        resumeToken = nil
        markSeq = 0
        lastAckSeq = 0

        currentStatus = .closed
    }

    /// Drops the socket and every listener bound to it. Leaving listeners
    /// attached across a reconnect is exactly how a server event ends up
    /// delivered two, three, four times.
    private func teardownSocket() {
        socket?.removeAllHandlers()
        manager?.disconnect()
        socket = nil
        manager = nil
    }

    /// `Encodable` -> `[String: Any]` bridge so a typed payload struct can
    /// be handed to socket.io-client-swift's `SocketData`-based `emit`.
    private func socketPayload(_ value: some Encodable) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(value) else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }
}
