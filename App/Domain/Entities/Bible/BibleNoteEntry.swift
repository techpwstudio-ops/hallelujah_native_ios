import Foundation

/// One row of the local "My Notes" ledger (`BibleRepository.fetchLocalNotes`)
/// — backed by `CachedVerseNote`, accumulated on-device as chapters are read
/// or notes are saved. There is no bulk "list all my notes" backend endpoint
/// (confirmed absent from `book.routes.js` by grep); Dart's own equivalent
/// screen (`book_page_menu_sheet.dart`'s `showBookNotes`) is likewise backed
/// purely by its local Realm cache, not a live fetch — this mirrors that.
struct BibleNoteEntry: Sendable, Equatable, Identifiable {
    var id: String { verseID }
    let verseID: String
    let bookNumber: Int
    let chapterNumber: Int
    let verseNumber: Int
    let content: String
    let updatedAt: Date
    /// Resolved from the cached chapter that holds this verse; `nil` when
    /// that chapter was never cached on this device.
    var verseText: String? = nil
    var languageName: String? = nil
}
