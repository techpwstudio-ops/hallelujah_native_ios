import Foundation
import Observation

/// Ports `_CreatePlaylistPageState._submit`
/// (`lib/views/library/create_playlist.dart`): one screen backs both create
/// (`userPlaylistID == nil`) and rename (non-nil), same `_isEditing` split
/// Dart makes off the same field. Rename pre-fill reads
/// `repository.fetchPlaylist(id:)` — Dart instead reads a cached Realm row
/// (`getRealm().find<UserPlaylist>`), which this app has no local-cache
/// equivalent of, so a real network fetch stands in for it.
@MainActor
@Observable
final class CreatePlaylistViewModel {
    let userPlaylistID: String?
    let songID: String?

    private(set) var isLoadingExisting = false
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    private let repository: any UserPlaylistRepository
    private let logger = AppLogger(category: .content)

    var isEditing: Bool { userPlaylistID != nil }

    init(userPlaylistID: String?, songID: String?, container: DependencyContainer = .current) {
        self.userPlaylistID = userPlaylistID
        self.songID = songID
        repository = container.resolve()
    }

    /// Rename-mode pre-fill. Returns `nil` in create mode or on a failed
    /// fetch; either way the caller's own title field is left as it already
    /// is, and a fetch failure surfaces through `errorMessage` the same
    /// inline slot `submit(title:)` uses.
    func loadExistingTitle() async -> String? {
        guard let userPlaylistID else { return nil }
        isLoadingExisting = true
        defer { isLoadingExisting = false }
        do {
            return try await repository.fetchPlaylist(id: userPlaylistID).title
        } catch {
            logger.warning("fetch playlist \(userPlaylistID) failed: \(error)")
            errorMessage = "Couldn't load this playlist. Please try again."
            return nil
        }
    }

    /// `_submit` — trims, then creates or renames. The caller only invokes
    /// this once the trimmed title is already known non-empty (the submit
    /// button is disabled otherwise, in place of Dart's `showSnackBarToast`
    /// guard); the trim/empty check below is a defensive backstop, e.g.
    /// against the text field's return-key submit.
    func submit(title: String) async -> UserPlaylist? {
        guard !isSubmitting else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            if let userPlaylistID {
                return try await repository.renamePlaylist(id: userPlaylistID, title: trimmed)
            }
            return try await repository.createPlaylist(title: trimmed, songID: songID)
        } catch {
            logger.warning("submit playlist failed: \(error)")
            errorMessage = "Something went wrong. Please try again."
            return nil
        }
    }
}
