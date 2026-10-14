import Foundation

/// Decides whether a serve request for a placement may go to the server, and
/// remembers what the last one learned for a minute — so the app asks once,
/// not once per widget. Ports `AdServeGate` (`lib/ads/ad_serve_gate.dart`).
///
/// Each key (placement, plus the requested format when there is one — see
/// `keyFor`) is in one of four states:
///
///   - **no-fill, until T** — everyone is turned away until T.
///   - **filled, until T** — everyone is let straight through (each slot needs
///     its own creative, so each sends its own request).
///   - **probing** — a request is out and nothing is known yet. The first
///     caller is the probe; every other caller WAITS for its verdict instead
///     of sending a request of its own. Eight rail slots become one request
///     when there is no ad, and one request plus seven when there is.
///   - **unknown** — never asked, or the last answer has expired. The next
///     caller becomes the probe.
///
/// A probe that fails outright leaves nothing remembered, but the callers
/// waiting on it do not each retry.
@MainActor
final class AdServeGate {
    enum Verdict: Sendable, Equatable {
        case filled, noFill, failed
    }

    /// One in-flight probe and the callers waiting on its verdict.
    fileprivate final class Probe {
        var waiters: [UUID: CheckedContinuation<Verdict?, Never>] = [:]

        func complete(_ verdict: Verdict) {
            let pending = waiters
            waiters.removeAll()
            for continuation in pending.values { continuation.resume(returning: verdict) }
        }
    }

    /// How long "this placement has ads" is believed before the next caller
    /// probes again.
    let fillTTL: Duration
    /// How long a no-fill keeps a key quiet when the server named no
    /// `Retry-After` of its own.
    let defaultNoFillTTL: Duration
    /// The longest a caller waits on someone else's probe.
    let maxProbeWait: Duration

    private let now: () -> Date
    private var known: [String: (verdict: Verdict, until: Date)] = [:]
    private var probes: [String: Probe] = [:]

    init(
        fillTTL: Duration = .seconds(60),
        defaultNoFillTTL: Duration = .seconds(60),
        maxProbeWait: Duration = .seconds(20),
        now: @escaping () -> Date = Date.init
    ) {
        self.fillTTL = fillTTL
        self.defaultNoFillTTL = defaultNoFillTTL
        self.maxProbeWait = maxProbeWait
        self.now = now
    }

    /// The key a request is filed under: the placement AND the requested
    /// format, so "no video booked right now" does not silence audio ads.
    nonisolated static func keyFor(_ placement: String, _ assetType: String?) -> String {
        assetType.map { "\(placement):\($0)" } ?? placement
    }

    /// Asks to send a request for `key`. Nil means "don't — it is already
    /// known to be pointless", and the caller should treat it as a no-fill.
    /// Otherwise the caller holds a turn and MUST report what happened to it.
    /// `force` always lets the caller through without opening a probe.
    func admit(_ key: String, force: Bool = false) async -> AdServeTurn? {
        if force { return AdServeTurn(gate: self, key: key, probe: nil) }

        if let verdict = current(key) {
            return verdict == .filled ? AdServeTurn(gate: self, key: key, probe: nil) : nil
        }

        guard let probe = probes[key] else {
            let mine = Probe()
            probes[key] = mine
            return AdServeTurn(gate: self, key: key, probe: mine)
        }

        // Someone else is finding out. Take their answer rather than asking again.
        let wait = maxProbeWait
        let verdict: Verdict? = await withCheckedContinuation { continuation in
            let id = UUID()
            probe.waiters[id] = continuation
            Task { @MainActor [weak probe] in
                try? await Task.sleep(for: wait)
                probe?.waiters.removeValue(forKey: id)?.resume(returning: nil)
            }
        }
        return verdict == .filled ? AdServeTurn(gate: self, key: key, probe: nil) : nil
    }

    /// How much longer `key` stays quiet after a no-fill, or zero when it is
    /// free to ask. A fill is not a wait, so it reads as zero too.
    func noFillRemaining(_ key: String) -> TimeInterval {
        guard let entry = known[key], entry.verdict == .noFill else { return 0 }
        return max(0, entry.until.timeIntervalSince(now()))
    }

    /// Forgets everything remembered, so the next caller of each key probes
    /// afresh. Callers already waiting on a probe still hear its verdict.
    func reset() {
        known.removeAll()
    }

    private func current(_ key: String) -> Verdict? {
        guard let entry = known[key] else { return nil }
        if now() >= entry.until {
            known.removeValue(forKey: key)
            return nil
        }
        return entry.verdict
    }

    fileprivate func report(_ key: String, probe: Probe?, verdict: Verdict, ttl: TimeInterval?) {
        if let ttl {
            known[key] = (verdict, now().addingTimeInterval(ttl))
        }
        // Only the turn that opened the probe closes it.
        if let probe {
            probes.removeValue(forKey: key)
            probe.complete(verdict)
        }
    }

    fileprivate static func seconds(_ duration: Duration) -> TimeInterval {
        let parts = duration.components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}

/// One caller's permission to send a request, from `AdServeGate.admit`.
/// Reporting is idempotent — only the first report counts — so a `defer` can
/// always call `failed()` without checking whether an earlier line reported.
@MainActor
final class AdServeTurn {
    private let gate: AdServeGate
    private let key: String
    private let probe: AdServeGate.Probe?
    private var reported = false

    fileprivate init(gate: AdServeGate, key: String, probe: AdServeGate.Probe?) {
        self.gate = gate
        self.key = key
        self.probe = probe
    }

    /// The request was answered with an ad.
    func filled() {
        report(.filled, ttl: AdServeGate.seconds(gate.fillTTL))
    }

    /// The request was answered with nothing; ask again no sooner than
    /// `retryAfter` or the gate's default.
    func noFill(retryAfter: TimeInterval? = nil) {
        report(.noFill, ttl: retryAfter ?? AdServeGate.seconds(gate.defaultNoFillTTL))
    }

    /// The request never produced an answer. Remembers nothing, but releases
    /// anyone waiting on it.
    func failed() {
        report(.failed, ttl: nil)
    }

    private func report(_ verdict: AdServeGate.Verdict, ttl: TimeInterval?) {
        guard !reported else { return }
        reported = true
        gate.report(key, probe: probe, verdict: verdict, ttl: ttl)
    }
}
