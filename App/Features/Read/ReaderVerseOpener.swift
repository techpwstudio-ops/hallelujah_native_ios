import Foundation

/// `ReadService.openVerse` (`lib/services/read_service.dart`): a verse-of-day
/// push, a shared verse-of-day / Bible-verse link or a notification tap opens
/// the Read tab on that book/chapter and scrolls to the verse. Values arrive as
/// numbers or numeric strings (`int.tryParse('$value')`). The reader consumes
/// `ReaderNavigationStore.pendingTarget` whenever it mounts or loads.
enum ReaderVerseOpener {
    static func open(from item: [String: Any]) {
        guard let book = int(item["bookNumber"]), let chapter = int(item["chapterNumber"]) else { return }
        let verse = int(item["verseNumber"])
        Task { @MainActor in
            let store: ReaderNavigationStore = DependencyContainer.current.resolve()
            store.pendingTarget = ReaderNavigationStore.Target(
                bookNumber: book,
                chapterNumber: chapter,
                verseNumber: verse
            )
        }
    }

    static func int(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }
}
