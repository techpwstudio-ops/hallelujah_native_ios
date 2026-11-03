import Foundation
import Testing
@testable import Hallelujah

/// The transcript file (`episodeTranscript.url`) decoded and flattened.
struct TranscriptFileDTOTests {
    private func decodeFile(_ data: Data) throws -> EpisodeTranscriptFile? {
        try JSONDecoder().decode(TranscriptFileDTO.self, from: data).toDomain()
    }

    @Test func transcriptV2FlattensWordsAndSegments() throws {
        let file = try #require(try decodeFile(EpisodeTimelineFixtures.data(named: "transcript-v2")))

        #expect(file.version == 2)
        #expect(file.language == "te")
        #expect(file.words.count == 15)
        #expect(file.startsMs.first == 1200)
        #expect(file.endsMs.last == 11_000)
        #expect(file.segments.map(\.speaker) == ["S1", "S2", "S1"])
        #expect(file.segments[1].wordRange == 6..<9)
        #expect(file.words[6] == "Thank")
    }

    @Test func teluguWordsAreKeptWhole() throws {
        let file = try #require(try decodeFile(EpisodeTimelineFixtures.data(named: "transcript-v2")))

        #expect(file.words[9] == "దేవుడు")
        #expect(file.words[10] == "మనలను")
    }

    @Test func unsupportedFormatGivesNoTranscript() throws {
        let data = Data(#"{"format": 2, "version": 1, "segments": []}"#.utf8)

        #expect(try decodeFile(data) == nil)
    }

    @Test func missingFormatGivesNoTranscript() throws {
        let data = Data(#"{"version": 1, "segments": []}"#.utf8)

        #expect(try decodeFile(data) == nil)
    }

    @Test func aMalformedWordIsDroppedAndTheRestKept() throws {
        let data = Data("""
        {"format": 1, "version": 1, "segments": [
          {"speaker": null, "startMs": 0, "endMs": 900, "words": [
            [0, 300, "one"], ["bad", 1, 2], [400, 900, "two"]
          ]}
        ]}
        """.utf8)
        let file = try #require(try decodeFile(data))

        #expect(file.words == ["one", "two"])
        #expect(file.segments.first?.speaker == nil)
    }
}
