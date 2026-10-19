import Foundation
@testable import Hallelujah

/// A scriptable `LibraryRepository` for store/view-model tests.
final class FakeLibraryRepository: LibraryRepository, @unchecked Sendable {
    struct Failure: Error {}

    var savedKeys: Set<String> = []
    var fetchSavedKeysError: Error?
    /// What `toggleSaved` answers; `nil` echoes the opposite of the current state.
    var toggleVerdict: Bool?
    var toggleError: Error?
    private(set) var toggleCalls: [(type: LibraryItemType, id: String)] = []

    func fetchCounts(songType: HomeContentType) async throws -> LibraryCounts {
        throw Failure()
    }

    func fetchItems(songType: HomeContentType, page: Int) async throws -> Paginated<LibraryEntry> {
        throw Failure()
    }

    func fetchSavedKeys() async throws -> Set<String> {
        if let fetchSavedKeysError { throw fetchSavedKeysError }
        return savedKeys
    }

    func toggleSaved(type: LibraryItemType, id: String) async throws -> Bool {
        toggleCalls.append((type, id))
        if let toggleError { throw toggleError }
        return toggleVerdict ?? !savedKeys.contains(type.key(for: id))
    }
}
