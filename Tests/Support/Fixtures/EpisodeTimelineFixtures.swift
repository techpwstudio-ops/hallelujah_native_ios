import Foundation

/// Loads the backend's episode-timeline contract fixtures (copied from
/// `gs_nh_backend/docs/fixtures/episode-timeline` into this target). Listener
/// fixtures wrap the song in `{ success, message, data }`; the decoders read `data`.
enum EpisodeTimelineFixtures {
    enum LoadError: Error {
        case missing(String)
    }

    private final class BundleToken {}

    static func data(named name: String) throws -> Data {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw LoadError.missing(name)
        }
        return try Data(contentsOf: url)
    }
}
