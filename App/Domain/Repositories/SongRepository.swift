import Foundation

/// `fetchSongById` (`lib/river_pods/song_repository.dart`) and
/// `ReportedSongsBloc.reportSong` (`lib/blocs/reported_songs/bloc.dart`) — the
/// two single-song server calls the song menu needs. Everything else about a
/// song (favourite, download, playlists) already has its own repository.
protocol SongRepository: Sendable {
    /// `GET /song/:id` — the detail view, the only response that carries
    /// `songCredits`, `transcripts` and each artist's `creatorId`.
    func fetchSong(id: String) async throws -> Song

    /// `POST /song/:id/report` with `{message}`. The server hides the song
    /// from the reporter afterwards, which is why the caller stops playback.
    func reportSong(id: String, message: String) async throws
}
