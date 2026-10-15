import Foundation
import Observation

/// Ports `RelatedContentService` (`lib/services/related_content_service.dart`):
/// the content related to a song — company playlists for music, creators for
/// episodes. One service, two consumers, one list: the player's related rail
/// renders all of it and the queue auto-continues into entry 0 when it ends
/// with repeat off, so what autoplay continues into is always the first card
/// the listener was already looking at.
///
/// Results are cached per `songId|excludeId` (40 entries, oldest evicted) and
/// concurrent identical requests share one in-flight task. Any failure yields
/// an empty result: "no recommendations" and "request failed" are the same to
/// both callers.
@MainActor
@Observable
final class RelatedContentService {
    static let maxCacheEntries = 40

    private let repository: any RelatedContentRepository
    private let playlists: any PlaylistRepository
    private let creators: any CreatorRepository
    private let logger = AppLogger(category: .content)

    @ObservationIgnored private var cache: [String: RelatedContent] = [:]
    @ObservationIgnored private var cacheOrder: [String] = []
    @ObservationIgnored private var inFlight: [String: Task<RelatedContent, Never>] = [:]

    init(
        repository: any RelatedContentRepository,
        playlists: any PlaylistRepository,
        creators: any CreatorRepository
    ) {
        self.repository = repository
        self.playlists = playlists
        self.creators = creators
    }

    nonisolated static func cacheKey(songId: String, excludeId: String?) -> String {
        "\(songId)|\(excludeId ?? "")"
    }

    /// Ranked content related to `songId`, strongest first. `excludeId` is the
    /// playlist or creator currently playing, so the rail never suggests (and
    /// autoplay never restarts) what just finished.
    func fetchForSong(_ songId: String, excludeId: String? = nil, limit: Int = 10) async -> RelatedContent {
        let key = Self.cacheKey(songId: songId, excludeId: excludeId)
        if let cached = cache[key] { return cached }
        if let pending = inFlight[key] { return await pending.value }

        let repository = repository
        let logger = logger
        let task = Task<RelatedContent, Never> {
            do {
                return try await repository.fetchRelated(songId: songId, excludeId: excludeId, limit: limit)
            } catch {
                logger.warning("related content fetch failed: \(error)")
                return .empty
            }
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        store(result, for: key)
        return result
    }

    /// The cached result, so the rail can paint instantly on a back-navigation.
    func cached(for songId: String, excludeId: String? = nil) -> RelatedContent? {
        cache[Self.cacheKey(songId: songId, excludeId: excludeId)]
    }

    /// Songs to queue when auto-continuing into `item`, in play order. First
    /// page only: a playlist by its track list, a creator by their episodes
    /// (dropping a listener into music after an episode ends is exactly the
    /// jarring hand-off this feature exists to avoid).
    func fetchQueue(for item: RelatedItem) async -> [Song] {
        switch item.kind {
        case .playlist:
            return (try? await playlists.fetchSongs(playlistId: item.id, owner: .company, page: 1))?.items ?? []
        case .creator:
            return (try? await creators.fetchSongs(creatorId: item.id, type: .episode, page: 1))?.items ?? []
        }
    }

    /// Called on logout so one account's recommendations never leak into the
    /// next session on a shared device.
    func clear() {
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        cache.removeAll()
        cacheOrder.removeAll()
    }

    private func store(_ result: RelatedContent, for key: String) {
        if cache[key] == nil { cacheOrder.append(key) }
        cache[key] = result
        while cacheOrder.count > Self.maxCacheEntries {
            cache[cacheOrder.removeFirst()] = nil
        }
    }
}
