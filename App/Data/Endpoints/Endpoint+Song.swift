import Foundation

extension Endpoint {
    // MARK: Single song (song menu) — `end_points.dart`'s `accessSongApi`/
    // `reportSongApi`.

    static func songDetail(id: String) -> Endpoint {
        .get("/song/\(id)")
    }

    static func reportSong(id: String) -> Endpoint {
        .post("/song/\(id)/report")
    }
}
