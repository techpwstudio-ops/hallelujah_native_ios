import Foundation

/// T55 — the recent-searches list `BibleSearchPanel` renders above results
/// when the search field is empty (`bible_search_panel.dart`'s
/// `_buildRecentSearches`), backed there by a `SharedPreferences`-persisted
/// JSON list capped at 8. Mirrors `RecentSearchStore` (T40)'s shape exactly;
/// a separate store because the two lists are unrelated features with
/// different persisted key/entry types, not because the pattern differs.
@MainActor
@Observable
final class BibleRecentSearchStore {
    private struct Record: Sendable, Equatable, Codable {
        let result: BibleSearchResult
        let recordedAt: Date
    }

    private static let storageKey = "bible_recent_search"
    /// Matches Dart's `_maxRecentSearches = 8` in `bible_search_panel.dart`.
    private static let maxEntries = 8

    private var records: [Record] = []
    private let keyValueStore: any KeyValueStoring
    private let clock: any ClockProviding

    var entries: [BibleSearchResult] {
        records.sorted { $0.recordedAt > $1.recordedAt }.map(\.result)
    }

    init(keyValueStore: any KeyValueStoring, clock: any ClockProviding) {
        self.keyValueStore = keyValueStore
        self.clock = clock
        if let data = keyValueStore.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([Record].self, from: data) {
            records = decoded
        }
    }

    /// Upsert keyed by `reference` (book/chapter/verse), not `id`: a repeat
    /// tap on the same verse from two different search queries should
    /// collapse to one history row, same as Dart deduping recent searches by
    /// their rendered reference string.
    func record(_ result: BibleSearchResult) {
        records.removeAll { $0.result.reference == result.reference }
        records.append(Record(result: result, recordedAt: clock.now()))
        if records.count > Self.maxEntries {
            records = Array(records.sorted { $0.recordedAt > $1.recordedAt }.prefix(Self.maxEntries))
        }
        persist()
    }

    func remove(reference: String) {
        records.removeAll { $0.result.reference == reference }
        persist()
    }

    func clearAll() {
        records.removeAll()
        keyValueStore.removeValue(forKey: Self.storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        keyValueStore.setData(data, forKey: Self.storageKey)
    }
}
