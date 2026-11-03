import Foundation

/// One in-memory copy of `GET /song/:id` per song, shared by everything that
/// needs the detail-only fields (I2). Concurrent requests for one song share a
/// single network call. Entries live for `ttl` seconds and are never written to
/// disk, because the signed URLs inside them expire.
actor SongDetailCache {
    private struct Entry {
        let song: Song
        let fetchedAt: Date
    }

    private let repository: any SongRepository
    private let clock: any ClockProviding
    private let ttl: TimeInterval
    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<Song, Error>] = [:]

    init(repository: any SongRepository, clock: any ClockProviding = SystemClock(), ttl: TimeInterval = 300) {
        self.repository = repository
        self.clock = clock
        self.ttl = ttl
    }

    /// The song's detail. `forceRefresh` skips a fresh entry, for when a signed
    /// URL inside it has been refused.
    func song(id: String, forceRefresh: Bool = false) async throws -> Song {
        let now = clock.now()
        if !forceRefresh, let entry = entries[id], now.timeIntervalSince(entry.fetchedAt) < ttl {
            return entry.song
        }
        if let pending = inFlight[id] {
            return try await pending.value
        }
        let source = repository
        let task = Task<Song, Error> { try await source.fetchSong(id: id) }
        inFlight[id] = task
        defer { inFlight[id] = nil }
        let song = try await task.value
        entries[id] = Entry(song: song, fetchedAt: clock.now())
        return song
    }

    /// Drops everything, for sign-out (`SessionTeardown`).
    func clear() {
        entries = [:]
        inFlight = [:]
    }
}
