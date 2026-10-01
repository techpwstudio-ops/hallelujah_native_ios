import Foundation

/// The public S3/CDN whole-book snapshot's JSON shape
/// (`bible-db-snapshot/:language/:bookNumber.json`), written by the
/// backend's `seedS3Bible` job from `buildBookVersesPayload`
/// (`src/services/bibleBook.service.js`). Unlike `BibleChapterResponseDTO`
/// (`GET /book/chapter/verses`), every verse row here already carries its
/// own `bookNumber`/`languageName` — no envelope-level threading needed.
struct BibleSnapshotResponseDTO: Decodable {
    let bookNumber: Int
    let languageName: String
    let chapters: [BibleSnapshotChapterDTO]
}

struct BibleSnapshotChapterDTO: Decodable {
    let chapterNumber: Int
    let verses: [BibleSnapshotVerseDTO]
}

struct BibleSnapshotVerseDTO: Decodable {
    let id: String
    let bookNumber: Int
    let chapterNumber: Int
    let verseNumber: Int
    let text: String

    func toDomain() -> BibleVerse {
        BibleVerse(id: id, bookNumber: bookNumber, chapterNumber: chapterNumber, verseNumber: verseNumber, text: text)
    }
}

extension BibleSnapshotResponseDTO {
    /// One `BibleChapter` per chapter in the snapshot, notes/highlights
    /// always empty (this is the public unauthenticated snapshot — those are
    /// per-user, only ever synced through `BibleRepository`'s authenticated
    /// endpoints). A chapter whose `verses` came back empty (a partially
    /// translated Bible — the backend's own `chapters` builder still emits
    /// the chapter row) is dropped: there is nothing to cache and nothing a
    /// re-download would recover, matching Dart's identical skip in
    /// `_downloadBook`.
    func toDomainChapters() -> [BibleChapter] {
        chapters.compactMap { chapter in
            guard !chapter.verses.isEmpty else { return nil }
            return BibleChapter(
                bookNumber: bookNumber,
                chapterNumber: chapter.chapterNumber,
                languageName: languageName,
                verses: chapter.verses.map { $0.toDomain() },
                notes: [],
                highlights: []
            )
        }
    }
}
