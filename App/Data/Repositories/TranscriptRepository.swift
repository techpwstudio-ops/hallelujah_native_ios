import Foundation

/// Downloads an episode's transcript file and keeps it on disk (Phase 2).
///
/// The cache key is `songId` + `version`, never the URL, because the signed URL
/// expires (contract §3). The download uses its own session with no app
/// credentials, since the CDN does not need them (I9). A 403 means the URL has
/// expired: the song is refetched once with `forceRefresh` and the download is
/// retried once. After that it gives up quietly and nothing is shown.
actor TranscriptRepository {
    private enum Fetch {
        case data(Data)
        case refused
        case failed
    }

    private let songDetailCache: SongDetailCache
    private let session: URLSession
    private let cache: DiskCache?

    init(songDetailCache: SongDetailCache, session: URLSession = URLSession(configuration: .default)) {
        self.songDetailCache = songDetailCache
        self.session = session
        cache = try? DiskCache(directoryName: "transcripts")
    }

    /// The transcript for a `ready` episode, or `nil` when it cannot be had.
    func transcript(for info: EpisodeTranscriptInfo, songId: String) async -> EpisodeTranscriptFile? {
        let key = Self.cacheKey(songId: songId, version: info.version)
        if let stored = cache?.data(forKey: key), let file = await Self.parse(stored) {
            return file
        }
        guard let url = info.url else { return nil }
        switch await fetch(url) {
        case let .data(data):
            return await store(data, key: key)
        case .refused:
            guard let fresh = await refreshedURL(songId: songId) else { return nil }
            guard case let .data(data) = await fetch(fresh) else { return nil }
            return await store(data, key: key)
        case .failed:
            return nil
        }
    }

    static func cacheKey(songId: String, version: Int) -> String {
        "transcript:\(songId):v\(version)"
    }

    private func fetch(_ url: URL) async -> Fetch {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else { return .failed }
            switch http.statusCode {
            case 200: return .data(data)
            case 403: return .refused
            default: return .failed
            }
        } catch {
            return .failed
        }
    }

    private func refreshedURL(songId: String) async -> URL? {
        let song = try? await songDetailCache.song(id: songId, forceRefresh: true)
        return song?.episodeTimeline?.transcript.url
    }

    /// Parses first, then writes, so an unsupported file is never cached.
    private func store(_ data: Data, key: String) async -> EpisodeTranscriptFile? {
        guard let file = await Self.parse(data) else { return nil }
        try? cache?.setData(data, forKey: key)
        return file
    }

    /// Sign-out (decision D-I5): removes every stored transcript file. The files
    /// are cheap to fetch again, so only the contents are removed, not the folder.
    static func removeAll() {
        guard let caches = try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }
        let directory = caches.appendingPathComponent("transcripts", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Decoding runs off the main actor (the repo's existing pattern for large payloads).
    private static func parse(_ data: Data) async -> EpisodeTranscriptFile? {
        await Task.detached(priority: .utility) {
            try? JSONDecoder().decode(TranscriptFileDTO.self, from: data).toDomain()
        }.value
    }
}
