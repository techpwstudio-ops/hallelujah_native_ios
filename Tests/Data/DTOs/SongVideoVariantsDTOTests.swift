import Foundation
import Testing
@testable import Hallelujah

/// `SongDTO.videoVariants` / `videoVariantsMeta.source`: additive and lenient, so a bad value never
/// costs the song.
struct SongVideoVariantsDTOTests {
    private func decode(_ fields: String) throws -> Song {
        let json = Data("""
        {"data": {"id": "e1", "title": "Episode", "type": "episode", "transcripts": []\(fields)}}
        """.utf8)
        return try JSONDecoder().decode(SongDetailResponseDTO.self, from: json).data.toDomain()
    }

    @Test func decodesVariantsAndSource() throws {
        let song = try decode("""
        , "videoVariants": "480p.mp4,720p.mp4,1080p.mp4",
        "videoVariantsMeta": {
          "480p": {"width": 854, "height": 480},
          "source": {"width": 3840, "height": 2160, "codec": "hevc", "profile": "Main 10",
                     "fps": 29.97, "bitrate": 18000000, "pixFmt": "yuv420p10le"}
        }
        """)
        #expect(song.videoVariants == "480p.mp4,720p.mp4,1080p.mp4")
        #expect(song.videoSource?.codec == "hevc")
        #expect(song.videoSource?.width == 3840)
        #expect(song.videoSource?.height == 2160)
        #expect(song.videoSource?.fps == 29.97)
        #expect(song.videoSource?.bitrate == 18_000_000)
        #expect(song.videoSource?.shortSide == 2160)
    }

    @Test func missingAndNullFieldsMeanNoVariants() throws {
        for fields in ["", #", "videoVariants": null, "videoVariantsMeta": null"#] {
            let song = try decode(fields)
            #expect(song.videoVariants == nil)
            #expect(song.videoSource == nil)
        }
    }

    @Test func blankVariantStringsAreNil() throws {
        for value in ["", "  ", "null"] {
            #expect(try decode(#", "videoVariants": "\#(value)""#).videoVariants == nil)
        }
    }

    @Test func wrongTypesDropOnlyThemselves() throws {
        for value in ["42", "true", "[1]", #"{"a": 1}"#] {
            let song = try decode(#", "videoVariants": \#(value), "primaryArtists": "Pastor""#)
            #expect(song.videoVariants == nil)
            #expect(song.id == "e1")
            #expect(song.primaryArtists == "Pastor")
        }
        for value in ["42", #""text""#, "[1]", "true"] {
            let song = try decode(#", "videoVariantsMeta": \#(value), "primaryArtists": "Pastor""#)
            #expect(song.videoSource == nil)
            #expect(song.primaryArtists == "Pastor")
        }
    }

    @Test func aMalformedSourceKeepsTheVariantsAndTheGoodFields() throws {
        let song = try decode("""
        , "videoVariants": "480p.mp4",
        "videoVariantsMeta": {"source": {"width": "wide", "height": 1080, "codec": 264, "fps": "x"}}
        """)
        #expect(song.videoVariants == "480p.mp4")
        #expect(song.videoSource?.width == nil)
        #expect(song.videoSource?.height == 1080)
        #expect(song.videoSource?.codec == nil)
        #expect(song.videoSource?.fps == nil)
        #expect(song.videoSource?.shortSide == nil)
    }

    @Test func aSourceThatIsNotAnObjectLeavesNoSource() throws {
        let song = try decode(#", "videoVariantsMeta": {"source": "h264"}, "videoVariants": "480p.mp4""#)
        #expect(song.videoSource == nil)
        #expect(song.videoVariants == "480p.mp4")
    }

    @Test func variantsSurviveFavouriting() throws {
        let song = Song.fixture(
            videoFile: "a/original.mp4",
            videoVariants: "480p.mp4",
            videoSource: VideoSourceInfo(codec: "h264", width: 1280, height: 720, fps: 30, bitrate: nil)
        ).withFavorited(true)
        #expect(song.videoVariants == "480p.mp4")
        #expect(song.videoSource?.codec == "h264")
    }
}
