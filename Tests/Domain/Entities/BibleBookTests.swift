import Foundation
import Testing
@testable import Hallelujah

struct BibleBookTests {
    private let genesis = BibleBook(
        id: "b1",
        bookNumber: 1,
        name: "Genesis",
        chapters: 50,
        translations: [
            BibleBookTranslation(language: "Telugu", translatedName: "ఆదికాండము"),
            BibleBookTranslation(language: "Hindi", translatedName: nil),
        ]
    )

    @Test func translateMatchesLanguageCaseInsensitively() {
        #expect(genesis.translate("telugu") == "ఆదికాండము")
        #expect(genesis.translate("TELUGU") == "ఆదికాండము")
    }

    @Test func translateFallsBackToCanonicalName() {
        #expect(genesis.translate("English") == "Genesis")
        #expect(genesis.translate(nil) == "Genesis")
        // A translation row without a translated name falls back too.
        #expect(genesis.translate("Hindi") == "Genesis")
    }

    @Test func decodesWithoutTranslations() throws {
        let json = #"{"id":"b2","bookNumber":2,"name":"Exodus","chapters":40}"#
        let book = try JSONDecoder().decode(BibleBook.self, from: Data(json.utf8))
        #expect(book.translations.isEmpty)
        #expect(book.translate("Telugu") == "Exodus")
    }

    @Test func initDTOCarriesTranslations() throws {
        let json = """
        {"id":"b1","name":"Genesis","chapters":50,"bookNumber":1,
         "translations":[{"id":"t","bibleBookId":"b1","language":"Telugu","translatedName":"ఆదికాండము"}]}
        """
        let dto = try JSONDecoder().decode(BibleBookDTO.self, from: Data(json.utf8))
        let book = try #require(dto.toDomain())
        #expect(book.translate("telugu") == "ఆదికాండము")
    }
}
