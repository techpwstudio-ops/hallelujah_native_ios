import Foundation

/// T54 — persists `ReaderPreferences` (font size + theme). A genuinely new,
/// native-only setting with no Dart precedent to port: `bookBgColor`/
/// `bookTextColor` `StorageService` keys exist in the real app but are read
/// and never written anywhere, and font size is hardcoded `18.0` with no
/// picker UI in Dart — see the T54 grounding summary. Plain helper, not
/// DI-registered; `ReaderViewModel` constructs it directly from an
/// already-resolved `KeyValueStoring`, same tier `CurrentUserStore` uses for
/// its own small JSON blob.
final class ReaderPreferencesStore {
    private let keyValueStore: any KeyValueStoring
    private let key = "bible.reader.preferences"

    init(keyValueStore: any KeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    func load() -> ReaderPreferences {
        guard let data = keyValueStore.data(forKey: key),
              let decoded = try? JSONDecoder().decode(ReaderPreferences.self, from: data) else {
            return .standard
        }
        return decoded
    }

    func save(_ preferences: ReaderPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        keyValueStore.setData(data, forKey: key)
    }
}
