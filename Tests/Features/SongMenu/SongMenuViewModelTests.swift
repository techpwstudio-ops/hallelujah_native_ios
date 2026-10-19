import Testing
@testable import Hallelujah

/// Only the pure parts of `SongMenuViewModel` are unit-tested; its actions
/// need the full dependency graph (download engine, audio engine, queue) and
/// are covered by the manual/UI pass.
@MainActor
struct SongMenuViewModelTests {
    @Test func artistIDPrefersTheSongsOwnCreator() {
        let song = Song.fixture()
        #expect(SongMenuViewModel.artistID(of: song) == nil)
    }

    @Test func outcomesCompareByValue() {
        #expect(SongMenuOutcome.message("a") == .message("a"))
        #expect(SongMenuOutcome.message("a") != .notice("a"))
        #expect(SongMenuOutcome.goToArtist("1") == .goToArtist("1"))
    }
}
