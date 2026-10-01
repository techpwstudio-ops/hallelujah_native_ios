import Foundation

/// The reader's last-viewed position, persisted via `ReaderPositionStore` —
/// mirrors Dart's `StorageService` writes in `bible_bloc.dart`'s setters.
struct ReaderPosition: Sendable, Equatable, Codable {
    var bookNumber: Int
    var chapterNumber: Int
    var languageName: String

    static let standard = ReaderPosition(bookNumber: 1, chapterNumber: 1, languageName: "English")
}
