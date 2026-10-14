import Foundation
import Intents

/// "Hey Siri, play <song> in Hallelujah" — the app-side half of the
/// `SiriIntentsExtension` hand-off (ports `playFromSiriSearch`,
/// `ios/CarPlaySceneDelegate.swift` + `SceneDelegate.swift`).
///
/// The extension runs in its own process with no access to the session, so it
/// only captures the spoken text and returns `.continueInApp`; iOS then
/// delivers an `NSUserActivity` carrying the resolved `INPlayMediaIntent` to
/// the running app (phone scene via `onContinueUserActivity`, CarPlay scene via
/// `scene(_:continue:)`), which lands here to search and play.
@MainActor
final class SiriPlayService {
    /// `NSUserActivityTypes` entry in `Info.plist`.
    static let activityType = "INPlayMediaIntent"

    private let search: any SearchRepository
    private let queueController: QueueController
    private let logger = AppLogger(category: .playback)

    init(container: DependencyContainer = .current) {
        search = container.resolve()
        queueController = container.resolve()
    }

    /// The spoken search text, or `nil` when the activity isn't a play-media
    /// intent or carries nothing to search for.
    nonisolated static func query(from activity: NSUserActivity) -> String? {
        guard let intent = activity.interaction?.intent as? INPlayMediaIntent else { return nil }
        let raw = intent.mediaItems?.first?.title ?? intent.mediaSearch?.mediaName
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Searches for `query` and plays the best music match. Returns whether
    /// anything started playing.
    @discardableResult
    func play(query: String) async -> Bool {
        guard let results = try? await search.search(
            query: query, filter: nil,
            musicPage: 1, episodePage: 1, creatorPage: 1, playlistPage: 1,
            userPlaylistId: nil
        ) else {
            logger.warning("Siri search failed for \"\(query)\"")
            return false
        }
        guard let song = Self.bestMatch(in: results) else {
            logger.info("Siri search found nothing for \"\(query)\"")
            return false
        }
        await queueController.play(
            songs: [song], startIndex: 0,
            source: QueueAttribution(playerType: .search, id: nil, title: query)
        )
        return true
    }

    @discardableResult
    func play(from activity: NSUserActivity) async -> Bool {
        guard let query = Self.query(from: activity) else { return false }
        return await play(query: query)
    }

    /// The top result when it is a song, else the first music hit, else the
    /// first episode.
    nonisolated static func bestMatch(in results: SearchResults) -> Song? {
        if case .song(let song)? = results.topResult { return song }
        return results.music.items.first ?? results.episodes.items.first
    }
}
