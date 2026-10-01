import Foundation

/// T56 — mirrors `VerseOfDayHistoryBloc`'s two `StorageService` keys
/// (`lib/blocs/verse_of_day_history/bloc.dart`): `last_verse_of_day_id`
/// (the currently-displayed verse's id, used to look the full object up in
/// `VerseOfDayCache`) and `verse_of_day_hidden_until` (ISO8601; "Hide for
/// today" sets it to the start of tomorrow, "Unhide" clears it). Plain
/// helper, not DI-registered — same shape and rationale as
/// `ReaderPositionStore`, constructed directly wherever it's needed.
final class VerseOfDayLocalStore {
    private let keyValueStore: any KeyValueStoring
    private let lastIDKey = "last_verse_of_day_id"
    private let hiddenUntilKey = "verse_of_day_hidden_until"

    init(keyValueStore: any KeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    var lastVerseOfDayID: String? {
        get { keyValueStore.string(forKey: lastIDKey) }
        set { keyValueStore.setString(newValue, forKey: lastIDKey) }
    }

    /// `state.isHiddenToday`: `DateTime.now().isBefore(hiddenUntil)`.
    var isHiddenToday: Bool {
        guard
            let stored = keyValueStore.string(forKey: hiddenUntilKey),
            let hiddenUntil = ISO8601DateFormatter().date(from: stored)
        else {
            return false
        }
        return Date() < hiddenUntil
    }

    /// `DateTime(now.year, now.month, now.day + 1)` — the start of
    /// tomorrow, local time.
    func hideForToday() {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else { return }
        keyValueStore.setString(ISO8601DateFormatter().string(from: startOfTomorrow), forKey: hiddenUntilKey)
    }

    func unhide() {
        keyValueStore.removeValue(forKey: hiddenUntilKey)
    }
}
