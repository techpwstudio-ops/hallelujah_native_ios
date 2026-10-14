import Foundation

/// `{ data: <song> }` — `fetchSongById` reads `response.data['data']`.
struct SongDetailResponseDTO: Decodable, Sendable {
    let data: SongDTO
}

/// `{ message }` — `ReportedSongsBloc.reportSong`'s request body.
struct ReportSongRequestDTO: Encodable, Sendable {
    let message: String
}

/// Error body shape (`body['message']` is what Dart toasts on a non-200).
struct SongMessageResponseDTO: Decodable, Sendable {
    let message: String?
}
