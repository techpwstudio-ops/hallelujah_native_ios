import Foundation

/// Caches the last successful `/v2/home/layout/:type?withSections=N`
/// response, one per `HomeContentType`, keyed straight off the raw response
/// bytes rather than a separate hand-maintained cache schema — decoding a
/// cached blob goes through the exact same `HomeLayoutResponseDTO.toDomain()`
/// path a live response would, so there is no second decode path to drift
/// out of sync with the first. Mirrors `CurrentUserStore`'s
/// `KeyValueStoring`-backed, one-blob-per-key shape (T20).
///
/// Deliberately not a per-row relational cache (Dart's Realm-backed
/// `HomeV2Section` writes every song/playlist/creator to its own table) —
/// this covers T28's literal Done criterion ("offline shows cache") for the
/// first-paint window only, which is what `/layout?withSections=N` already
/// returns in one response. A fuller per-row cache (surviving past the
/// first-paint window, shared across screens) is future work once something
/// besides the home screen also needs offline content.
actor HomeFeedCache {
    private let keyValueStore: any KeyValueStoring

    init(keyValueStore: any KeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    /// Not persisted when `HomeLayout.degraded` — a degraded manifest is
    /// explicitly not meant to be cached for the session (`HOME_V2_API.md`
    /// §3.1), so a caller checks that before calling this rather than this
    /// method re-parsing `rawResponse` itself to check.
    func store(rawResponse: Data, type: HomeContentType) {
        keyValueStore.setData(rawResponse, forKey: key(for: type))
    }

    func load(type: HomeContentType) -> HomeLayout? {
        guard let data = keyValueStore.data(forKey: key(for: type)),
              let decoded = try? JSONDecoder().decode(HomeLayoutResponseDTO.self, from: data) else {
            return nil
        }
        return decoded.toDomain()
    }

    func clear(type: HomeContentType) {
        keyValueStore.removeValue(forKey: key(for: type))
    }

    private func key(for type: HomeContentType) -> String { "homeLayout.\(type.rawValue)" }
}
