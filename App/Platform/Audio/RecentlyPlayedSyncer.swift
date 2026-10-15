import Foundation

/// Ports the fire-and-forget `syncToRecentlyPlayedSongApi` POST at the end of
/// `SongAnalyticsManager.startSession` (`POST /song/:id/recent`). It tells the
/// server WHERE a play came from (`source`/`sourceId`/`sourceRank`/
/// `searchQuery`) so the home "Continue Your Journey" rail can collapse a
/// listening session onto its container. Failure is ignored: attribution must
/// never be able to fail a play.
struct RecentlyPlayedSyncer: Sendable {
    struct Payload: Sendable, Equatable {
        let songID: String
        let sessionID: String
        let playSource: String?
        let sourceID: String?
        let sourceRank: Int?
        let searchQuery: String?
    }

    private let client: HTTPClient

    init(client: HTTPClient) {
        self.client = client
    }

    func sync(_ payload: Payload) {
        let body = Self.body(for: payload)
        let endpoint = Self.endpoint(songID: payload.songID)
        Task { [client] in
            _ = try? await client.send(endpoint, body: body)
        }
    }

    static func endpoint(songID: String) -> Endpoint {
        .post("/song/\(songID)/recent")
    }

    /// Same optional-key shape as the Dart map literal: absent keys are
    /// omitted, an empty `searchQuery` is omitted, `sessionId` is always sent.
    static func bodyDictionary(for payload: Payload) -> [String: Any] {
        var map: [String: Any] = ["sessionId": payload.sessionID]
        if let source = payload.playSource { map["source"] = source }
        if let sourceID = payload.sourceID { map["sourceId"] = sourceID }
        if let rank = payload.sourceRank { map["sourceRank"] = rank }
        if let query = payload.searchQuery, !query.isEmpty { map["searchQuery"] = query }
        return map
    }

    static func body(for payload: Payload) -> Data? {
        try? JSONSerialization.data(withJSONObject: bodyDictionary(for: payload))
    }

    /// `sourceIdFromPlayerId` (`lib/blocs/player/state.dart:32-39`): the
    /// container id, or `nil` when it is absent, empty or the literal "null".
    static func sourceID(from attributionID: String?) -> String? {
        guard let attributionID, !attributionID.isEmpty, attributionID != "null" else { return nil }
        return attributionID
    }
}
