import Foundation

/// What plays after a queue runs out — worked out ahead of time. Ports
/// `_PreparedHandoff` (`lib/blocs/player/bloc.dart`).
struct PreparedHandoff: Sendable, Equatable {
    /// The queue-ending song this was prepared for. Only valid while the
    /// queue still ends on it.
    let afterSongID: String
    let title: String
    let source: QueueAttribution
    let songs: [Song]
}

/// A queue the app displaced with an automatic hand-off, remembered so that
/// Previous on the hand-off queue's first track can return to it
/// (`_QueueOrigin` / `_resumePreviousQueue`).
struct QueueOrigin: Sendable, Equatable {
    let songs: [Song]
    let currentSongID: String
    let source: QueueAttribution
}

/// How a queue relates to the one it replaces (`QueueContinuity`).
enum QueueContinuity: Sendable, Equatable {
    /// The user picked this: the queues behind it are forgotten.
    case fresh
    /// The app chose this when the queue ran out: the outgoing queue is
    /// remembered for Previous.
    case handoff
    /// Going BACK to a remembered queue; the entry was already popped.
    case restore
}

/// The pure, network-bounded half of the end-of-queue hand-off
/// (`_resolveHandoff` / `_prepareCandidate` in `PlayerBloc`): walk the ranked
/// related list, load each candidate's track list, and return the first that
/// has anything playable.
///
/// Not ported: `_anyCompanyPlaylist`, the Realm-backed last-resort fallback
/// (this app has no local company-playlist shelf to rank).
@MainActor
struct QueueHandoffResolver {
    /// Per-request ceiling inside the hand-off (`_handoffRequestTimeout`).
    static let requestTimeout: Duration = .seconds(6)
    /// How far down the ranking a hand-off will look (`_maxHandoffCandidates`).
    static let maxCandidates = 3
    /// `_maxQueueHistory`.
    static let maxHistory = 3

    let service: RelatedContentService

    func resolve(afterSong songID: String, excludeContainerID: String?) async -> PreparedHandoff? {
        let service = service
        let related = await Self.bounded(Self.requestTimeout) {
            await service.fetchForSong(songID, excludeId: excludeContainerID)
        }
        for item in (related?.items ?? []).prefix(Self.maxCandidates) {
            if let prepared = await prepare(item, after: songID) { return prepared }
        }
        return nil
    }

    func prepare(_ item: RelatedItem, after songID: String) async -> PreparedHandoff? {
        let service = service
        guard let fetched = await Self.bounded(Self.requestTimeout, { await service.fetchQueue(for: item) }) else {
            return nil
        }
        let songs = Self.candidateQueue(fetched, after: songID)
        guard !songs.isEmpty else { return nil }
        return PreparedHandoff(
            afterSongID: songID,
            title: item.title,
            source: Self.attribution(for: item),
            songs: songs
        )
    }

    /// `dedupeQueue(fetched)..remove(after)`: each song once, and never the
    /// song the hand-off happened after (a recommended playlist containing it
    /// would open by replaying the track the listener was handed off from).
    nonisolated static func candidateQueue(_ fetched: [Song], after songID: String) -> [Song] {
        var seen = Set<String>()
        return fetched.filter { $0.id != songID && seen.insert($0.id).inserted }
    }

    /// Mirrors the rail's kind -> destination mapping.
    nonisolated static func attribution(for item: RelatedItem) -> QueueAttribution {
        let type: PlayerType = switch item.kind {
        case .playlist: .companyPlaylist
        case .creator: .creator
        }
        return QueueAttribution(playerType: type, id: item.id, title: item.title)
    }

    /// Runs `operation`, returning nil if it has not finished within `limit`.
    nonisolated static func bounded<T: Sendable>(
        _ limit: Duration,
        _ operation: @escaping @Sendable () async -> T
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
