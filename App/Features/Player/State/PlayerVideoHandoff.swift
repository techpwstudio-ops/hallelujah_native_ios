import Foundation

/// Carries one episode's open silent video from a layer that is going away to a new layer for the
/// same episode, so the picture never drops back to the cover and the file is not opened again.
///
/// The artwork pager is why it exists. Shuffle reorders the queue and moves the playing episode to
/// another page, and `TabView(.page)` builds that page afresh. The old layer's task was cancelled,
/// which tore the player down, and the new layer opened the file from nothing: for about a second
/// the cover showed between two pictures. Now the layer going away leaves its player here, still
/// playing and still in step, and the new layer takes it over.
///
/// Every running layer holds the player it shows here under the episode's id, with an owner token.
/// The entry also says which file the player has open, so a new layer that wants another quality
/// keeps showing this one while it opens the new file (see `PlayerVideoStage`). A layer that starts
/// takes over whatever is held for its episode, whether the layer before it has let go yet or not,
/// since the two tasks run in either order. That layer then finds it no longer owns the player and
/// leaves it alone. A player that was let go and that no layer takes over within `graceMs` is
/// released.
@MainActor
final class PlayerVideoHandoff<Playback: VideoPlayback> {
    struct Held: Identifiable {
        let controller: PlayerVideoController
        let playback: Playback
        /// The file `playback` has open.
        let url: URL

        var id: ObjectIdentifier { ObjectIdentifier(controller) }
    }

    /// The episode a player belongs to.
    typealias Key = String

    /// Who runs a held player. A token, so a layer can tell whether it still does.
    typealias Owner = UUID

    private struct Entry {
        let held: Held
        /// The layer running the player; `nil` while it waits to be taken over.
        var owner: Owner?
        var expiry: Task<Void, Never>?
    }

    private let graceMs: Int
    private let sleep: @Sendable (Int) async -> Void
    private var entries: [Key: Entry] = [:]
    /// Expiries that have not finished, cancelled ones included, so a test can wait them out.
    private var pending: [UUID: Task<Void, Never>] = [:]

    /// `sleep` waits that many milliseconds; a test passes one that returns at once.
    init(
        graceMs: Int = 1_000,
        sleep: @escaping @Sendable (Int) async -> Void = { try? await Task.sleep(for: .milliseconds($0)) }
    ) {
        self.graceMs = graceMs
        self.sleep = sleep
    }

    /// What is held for `key`, running or waiting, without taking it over. A new layer starts from
    /// this so its first frame already draws the picture, whichever quality it wants.
    func peek(_ key: Key) -> Held? {
        entries[key]?.held
    }

    /// Takes over the player held for `key`, if there is one. It no longer expires, and the layer
    /// that ran it no longer owns it.
    func claim(_ key: Key, by owner: Owner) -> Held? {
        guard var entry = entries[key] else { return nil }
        entry.expiry?.cancel()
        entry.expiry = nil
        entry.owner = owner
        entries[key] = entry
        return entry.held
    }

    /// A layer that opened its own player holds it here while it runs.
    func hold(_ held: Held, for key: Key, by owner: Owner) {
        if let old = entries[key] {
            old.expiry?.cancel()
            if old.held.controller !== held.controller { old.held.controller.release() }
        }
        entries[key] = Entry(held: held, owner: owner)
    }

    func owns(_ key: Key, by owner: Owner) -> Bool {
        entries[key]?.owner == owner
    }

    /// Whether another layer has taken `key`'s player over from `owner`, which is when `owner`'s
    /// loop stops. Nothing held yet, or a player let go and waiting, is run by no one: a layer
    /// opening its first file (the switch to video) is not taken over and must keep going.
    func isTakenOver(_ key: Key, from owner: Owner) -> Bool {
        guard let running = entries[key]?.owner else { return false }
        return running != owner
    }

    /// The layer running `key`'s player is stopping. With `keep`, the player keeps playing for
    /// `graceMs` for a new layer to take over; without it (the video failed) it is released now.
    /// Nothing happens when another layer has taken the player over.
    func letGo(_ key: Key, by owner: Owner, keep: Bool) {
        guard var entry = entries[key], entry.owner == owner else { return }
        guard keep else {
            discard(key)
            return
        }
        entry.owner = nil
        let token = UUID()
        let expiry = Task { [graceMs, sleep] in
            defer { self.pending[token] = nil }
            await sleep(graceMs)
            guard !Task.isCancelled else { return }
            self.expire(key)
        }
        pending[token] = expiry
        entry.expiry = expiry
        entries[key] = entry
    }

    /// Releases whatever is held for `key` now, whoever runs it. A layer that starts hidden calls
    /// this: nothing is kept while the player is out of sight.
    func discard(_ key: Key) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        entry.expiry?.cancel()
        entry.held.controller.release()
    }

    /// Waits until every expiry that has been started has finished. For tests.
    func settle() async {
        while let task = pending.values.first {
            await task.value
        }
    }

    private func expire(_ key: Key) {
        guard let entry = entries[key], entry.owner == nil else { return }
        entries[key] = nil
        entry.held.controller.release()
    }
}
