import Foundation
import Testing
@testable import Hallelujah

/// `Song.transcripts` as `GET /api/song/:id` sends it: one row per language, the lines in the row's
/// own `transcripts` JSON (`{ meta, type, lines: [{ text, start, end }] }`, whole seconds).
struct LyricsTranscriptDTOTests {
    private func decode(_ rows: String) throws -> [LyricsTranscript] {
        let json = Data("""
        {"data": {"id": "e1", "title": "Episode", "type": "episode", "transcripts": \(rows)}}
        """.utf8)
        return try JSONDecoder().decode(SongDetailResponseDTO.self, from: json).data.toDomain().transcripts ?? []
    }

    private func row(id: String, language: String?, lines: String) -> String {
        let languageField = language.map { #""language": "\#($0)", "# } ?? ""
        return #"{"id": "\#(id)", \#(languageField)"syncStatus": "synced", "transcripts": {"meta": {"source": "local-parser"}, "type": "lyrics", "lines": \#(lines)}}"#
    }

    /// The staging row of "Is GOD Your First Response or Your Emergency Contact?", trimmed to two lines.
    @Test func readsTheServersRowShape() throws {
        let lines = try decode("[" + row(id: "b57d", language: "English", lines: """
        [{"end": 12, "text": "My question to you is", "start": 0},
         {"end": 17, "text": "Hello everyone", "start": 12}]
        """) + "]")

        #expect(lines.map(\.text) == ["My question to you is", "Hello everyone"])
        #expect(lines.map(\.startTime) == [0, 12])
        #expect(lines.map(\.endTime) == [12, 17])
        #expect(lines.map(\.id) == ["b57d-0", "b57d-1"])
        #expect(lines.allSatisfy { $0.language == "English" })
    }

    @Test func numericStringsAndFractionsAreRead() throws {
        let lines = try decode("[" + row(id: "r", language: "en", lines: """
        [{"start": "3", "end": "7.5", "text": "a"}]
        """) + "]")

        #expect(lines.first?.startTime == 3)
        #expect(lines.first?.endTime == 7.5)
    }

    @Test func aFailedRowAddsNothing() throws {
        let failed = #"{"id": "x", "language": "en", "syncStatus": "error", "transcripts": null}"#
        #expect(try decode("[\(failed)]").isEmpty)

        let lines = try decode("[\(failed), " + row(id: "ok", language: "Hindi", lines: #"[{"start": 0, "end": 4, "text": "b"}]"#) + "]")
        #expect(lines.map(\.id) == ["ok-0"])
    }

    @Test func aBadLineIsDroppedNotTheSong() throws {
        let lines = try decode("[" + row(id: "r", language: "en", lines: """
        [{"start": 0, "end": 4, "text": "kept"}, "not a line", {"start": 4, "end": 8, "text": "also kept"}]
        """) + "]")

        #expect(lines.map(\.text) == ["kept", "also kept"])
    }

    @Test func theOldFlatFormIsStillRead() throws {
        let lines = try decode(#"[{"id": "f1", "startTime": 2, "endTime": 5, "text": "flat"}]"#)

        #expect(lines.map(\.id) == ["f1"])
        #expect(lines.first?.startTime == 2)
    }

    // MARK: Language

    private func twoLanguages() throws -> [LyricsTranscript] {
        try decode("["
            + row(id: "en", language: "English", lines: #"[{"start": 0, "end": 4, "text": "Hello"}]"#) + ", "
            + row(id: "hi", language: "Hindi", lines: #"[{"start": 0, "end": 4, "text": "Namaste"}]"#) + ", "
            + row(id: "en2", language: "english", lines: #"[{"start": 0, "end": 4, "text": "Duplicate"}]"#)
            + "]")
    }

    @Test func theUsersBibleLanguageIsPreferred() throws {
        #expect(try twoLanguages().inPreferredLanguage("Hindi").map(\.text) == ["Namaste"])
        #expect(try twoLanguages().inPreferredLanguage(" hindi ").map(\.text) == ["Namaste"])
    }

    @Test func otherwiseTheFirstLanguageIsUsed() throws {
        #expect(try twoLanguages().inPreferredLanguage("Telugu").map(\.text) == ["Hello"])
        #expect(try twoLanguages().inPreferredLanguage(nil).map(\.text) == ["Hello"])
    }

    @Test func onlyTheFirstRowOfALanguageCounts() throws {
        #expect(try twoLanguages().inPreferredLanguage("English").map(\.text) == ["Hello"])
    }
}
