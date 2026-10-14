import Foundation
import Observation

/// T56 — carries a "jump to this verse" intent from wherever it originates
/// (a verse-of-day push tap, a verse-of-day deep link, a bare Bible-verse
/// deep link) into `ReaderView`, which is mounted lazily and may not exist
/// yet when the intent fires. Same shared-instance shape and rationale as
/// `AIChatNavigationStore` — see that type's doc comment.
@MainActor
@Observable
final class ReaderNavigationStore: Sendable {
    struct Target: Equatable {
        let bookNumber: Int
        let chapterNumber: Int
        /// Verse to scroll to and focus once the chapter loads (Flutter's
        /// `ReadOnContentChangedEvent.verseNo`).
        var verseNumber: Int? = nil
    }

    var pendingTarget: Target?
}
