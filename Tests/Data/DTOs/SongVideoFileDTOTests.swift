import Foundation
import Testing
@testable import Hallelujah

/// `SongDTO.videoFile`: additive and lenient (decision D25), so a bad value never costs the song.
struct SongVideoFileDTOTests {
    private func decode(_ fields: String) throws -> Song {
        let json = Data("""
        {"data": {"id": "e1", "title": "Episode", "type": "episode", "transcripts": []\(fields)}}
        """.utf8)
        return try JSONDecoder().decode(SongDetailResponseDTO.self, from: json).data.toDomain()
    }

    @Test func decodesTheKey() throws {
        let song = try decode(#", "videoFile": "ep/video-song/1-silent/original.mp4""#)
        #expect(song.videoFile == "ep/video-song/1-silent/original.mp4")
        #expect(song.hasVideo)
    }

    @Test func aMissingKeyMeansNoVideo() throws {
        let song = try decode("")
        #expect(song.videoFile == nil)
        #expect(!song.hasVideo)
    }

    @Test func aNullKeyMeansNoVideo() throws {
        let song = try decode(#", "videoFile": null"#)
        #expect(song.videoFile == nil)
        #expect(!song.hasVideo)
    }

    @Test func blankAndLiteralNullStringsMeanNoVideo() throws {
        for value in ["", "   ", "null", "undefined"] {
            let song = try decode(#", "videoFile": "\#(value)""#)
            #expect(song.videoFile == nil, "\(value.debugDescription) should read as no video")
        }
    }

    @Test func aNonStringValueDropsOnlyTheVideo() throws {
        for value in ["42", "true", "[1, 2]", #"{"a": 1}"#] {
            let song = try decode(#", "videoFile": \#(value), "primaryArtists": "Pastor""#)
            #expect(song.videoFile == nil, "\(value) should be dropped")
            #expect(song.id == "e1")
            #expect(song.primaryArtists == "Pastor")
        }
    }
}
