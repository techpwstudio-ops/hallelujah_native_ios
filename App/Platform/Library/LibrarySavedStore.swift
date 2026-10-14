import Foundation
import Observation

/// The set of saved library items (`LibraryItemsBloc`'s `savedKeys`,
/// `lib/blocs/library_items/bloc.dart`) — one shared instance, so every save
/// button in the app flips the moment any of them is tapped, including one
/// already on screen behind a sheet.
///
/// Reads the saved-id set once per session (`refreshIfNeeded`) and toggles
/// optimistically: the button flips immediately, reverts if the server fails,
/// and defers to the server's verdict when it disagrees (the item may have
/// been toggled from another device since the last sync).
@MainActor
@Observable
final class LibrarySavedStore {
    enum ToggleResult: Equatable {
        case saved
        case removed
        case failed
        /// A toggle for this item was already in flight.
        case ignored
    }

    private(set) var savedKeys: Set<String> = []
    private(set) var isLoaded = false

    private let repository: any LibraryRepository
    private var togglesInFlight: Set<String> = []
    private let logger = AppLogger(category: .content)

    init(repository: any LibraryRepository) {
        self.repository = repository
    }

    func isSaved(_ type: LibraryItemType, id: String) -> Bool {
        savedKeys.contains(type.key(for: id))
    }

    func refreshIfNeeded() async {
        guard !isLoaded else { return }
        await refresh()
    }

    /// Non-fatal on failure, as in Dart: every button renders "not saved"
    /// until a later refresh succeeds, and the server rejects a duplicate save.
    func refresh() async {
        do {
            savedKeys = try await repository.fetchSavedKeys()
            isLoaded = true
        } catch {
            logger.warning("library saved-ids sync failed: \(error)")
        }
    }

    func toggle(_ type: LibraryItemType, id: String) async -> ToggleResult {
        let key = type.key(for: id)
        guard togglesInFlight.insert(key).inserted else { return .ignored }
        defer { togglesInFlight.remove(key) }

        let wasSaved = savedKeys.contains(key)
        set(key, saved: !wasSaved)
        do {
            let serverSaved = try await repository.toggleSaved(type: type, id: id)
            if serverSaved != !wasSaved { set(key, saved: serverSaved) }
            return serverSaved ? .saved : .removed
        } catch {
            set(key, saved: wasSaved)
            logger.warning("library toggle failed: \(error)")
            return .failed
        }
    }

    /// Sign-out: another account must not inherit this one's saved set.
    func clear() {
        savedKeys = []
        isLoaded = false
    }

    private func set(_ key: String, saved: Bool) {
        if saved { savedKeys.insert(key) } else { savedKeys.remove(key) }
    }
}
