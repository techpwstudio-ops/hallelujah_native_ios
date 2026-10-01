import Foundation

/// T54 — persists `ReaderPosition` (book/chapter/language), so relaunching
/// the app reopens the reader where it was left. Mirrors Dart's own
/// `StorageService` writes in `bible_bloc.dart`'s setters, but through this
/// codebase's `KeyValueStoring` small-JSON-blob tier rather than Hive.
/// Plain helper, not DI-registered — same shape and rationale as
/// `ReaderPreferencesStore`, constructed directly by `ReaderViewModel`.
final class ReaderPositionStore {
    private let keyValueStore: any KeyValueStoring
    private let key = "bible.reader.position"

    init(keyValueStore: any KeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    func load() -> ReaderPosition {
        guard let data = keyValueStore.data(forKey: key),
              let decoded = try? JSONDecoder().decode(ReaderPosition.self, from: data) else {
            return .standard
        }
        return decoded
    }

    func save(_ position: ReaderPosition) {
        guard let data = try? JSONEncoder().encode(position) else { return }
        keyValueStore.setData(data, forKey: key)
    }
}
