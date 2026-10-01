import Foundation

/// T60 — a verse the reader wants Emet (the AI assistant) to explain,
/// independent of where it came from. Ports the Flutter app's
/// `lib/models/ai/verse_insight_target.dart`.
///
/// Every field is a plain value copy, not a live reference into
/// `BibleVerse`/`BibleBook` — this type deliberately outlives whatever
/// screen constructed it (a fresh conversation and streamed reply both take
/// real time, during which the Reader screen it came from could pop).
///
/// `bookName`/`languageName` are plain optional strings here, not looked up
/// from Bible data the way Flutter's `_referenceOf` falls back to
/// `getBibleBookByNumber(...).translate(language)` when absent — this native
/// port has no such lookup helper, and every call site that exists today
/// already has both values in hand (`ReaderViewModel.currentBook?.name`,
/// `currentLanguage`), so there's nothing to port that would ever run. See
/// `VerseInsightRequest.reference(for:language:)` for the (narrower)
/// fallback this type still gets: an empty/nil `bookName` degrades to a
/// bare "chapter:verse" reference, or `"this verse"` if that's empty too.
struct VerseInsightTarget: Sendable, Equatable {
    /// Text of the verse itself, without the leading verse number.
    let text: String

    let bookNumber: Int?
    let chapterNumber: Int?
    let verseNumber: Int?

    /// Book name as the calling surface already displays it.
    let bookName: String?

    /// Language this verse is being read in — the answer is asked for in it
    /// too (`VerseInsightRequest.fromTarget(target:selectedText:language:)`).
    let languageName: String?

    init(
        text: String,
        bookNumber: Int? = nil,
        chapterNumber: Int? = nil,
        verseNumber: Int? = nil,
        bookName: String? = nil,
        languageName: String? = nil
    ) {
        self.text = text
        self.bookNumber = bookNumber
        self.chapterNumber = chapterNumber
        self.verseNumber = verseNumber
        self.bookName = bookName
        self.languageName = languageName
    }

    /// A verse in the Bible reader. Mirrors Flutter's
    /// `VerseInsightTarget.fromBookVerse(BookVerse verse)`, adapted for this
    /// native `BibleVerse` (`App/Domain/Entities/Bible/BibleVerse.swift`),
    /// which — unlike Dart's `BookVerse` — carries neither a book name nor a
    /// language name of its own, so both are taken as explicit parameters
    /// from whatever the caller already has on screen (`ReaderView`'s
    /// `viewModel.currentBook?.name` / `viewModel.currentLanguage`) rather
    /// than left `nil` for a later data-layer lookup.
    ///
    static func fromBibleVerse(_ verse: BibleVerse, bookName: String?, languageName: String?) -> VerseInsightTarget {
        VerseInsightTarget(
            text: verse.text,
            bookNumber: verse.bookNumber,
            chapterNumber: verse.chapterNumber,
            verseNumber: verse.verseNumber,
            bookName: bookName,
            languageName: languageName
        )
    }

    /// T56 — the verse-of-day options sheet's "Ask Emet" row. Mirrors
    /// Flutter's `VerseInsightTarget.fromVerseOfDay(VerseOfDay verseOfDay)`
    /// field-for-field: `text` falls back to `""` (not optional here, unlike
    /// `VerseOfDay.verseText`) since a verse of the day can in principle
    /// reach the app without its text when the payload is incomplete — see
    /// `isEmpty` below, which is exactly how Flutter's own
    /// `VerseInsightTarget.isEmpty` on this factory's result is used to hide
    /// the "Ask Emet" row entirely when `text` is blank.
    static func fromVerseOfDay(_ verse: VerseOfDay) -> VerseInsightTarget {
        VerseInsightTarget(
            text: verse.verseText ?? "",
            bookNumber: verse.bookNumber,
            chapterNumber: verse.chapterNumber,
            verseNumber: verse.verseNumber,
            bookName: verse.bookName,
            languageName: verse.languageName
        )
    }

    /// Nothing to ask about.
    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
