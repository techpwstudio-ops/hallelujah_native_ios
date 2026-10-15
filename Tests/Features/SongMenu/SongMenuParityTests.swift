import Foundation
import Testing
@testable import GHallelujah

@MainActor
struct SongMenuParityTests {
    @Test func sleepLeftTextMatchesFormatDurationText() {
        #expect(SongMenuViewModel.sleepLeftText(seconds: 0) == "0 min Left")
        #expect(SongMenuViewModel.sleepLeftText(seconds: 45) == "45 sec Left")
        #expect(SongMenuViewModel.sleepLeftText(seconds: 300) == "5 min Left")
        #expect(SongMenuViewModel.sleepLeftText(seconds: 3600) == "1h Left")
        #expect(SongMenuViewModel.sleepLeftText(seconds: 3900) == "1h 5m Left")
    }

    @Test func playlistDateUsesDartFormat() {
        #expect(SongMenuViewModel.playlistDateText(nil) == "")
        let date = Date(timeIntervalSince1970: 0)
        let text = SongMenuViewModel.playlistDateText(date)
        #expect(text.count == "dd/MM/yy HH:mm:ss".count)
        #expect(text.split(separator: "/").count == 3)
    }

    @Test func listenersTextHidesZero() {
        #expect(CreatorDetailsViewModel.listenersText(0) == nil)
        #expect(CreatorDetailsViewModel.listenersText(12) == "12 Listeners")
    }

    @Test func userPlaylistDecodesSongIDs() throws {
        let json = #"{"id":"p1","title":"T","songs":[{"songId":"a"},{"songId":7},{}]}"#
        let dto = try JSONDecoder().decode(UserPlaylistDTO.self, from: Data(json.utf8))
        #expect(dto.toDomain().songIDs == ["a", "7"])
    }
}
