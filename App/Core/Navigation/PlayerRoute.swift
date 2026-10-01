import Foundation

/// Pushed on top of the full player inside its own `FullScreenDestination
/// .player` presentation — the rest of Dart's `playerOwnedRoutes`
/// (`lib/routes/routes.dart`) besides `AudioPlayerScreen` itself, which is
/// the presentation's root rather than a `PlayerRoute` case.
///
/// `SongLyricsPage` also takes a `TranscriptRepositoryModel?` in Dart
/// (`lib/views/home/SongLyricsPage.dart`) — a real domain model, and one
/// nothing native has yet. Dropped here rather than invented: whatever
/// builds the player can source the transcript for the song already
/// playing from its own playback state instead of threading it through
/// navigation.
enum PlayerRoute: Hashable, Sendable {
    case queue
    case lyrics(songTitle: String)
}
