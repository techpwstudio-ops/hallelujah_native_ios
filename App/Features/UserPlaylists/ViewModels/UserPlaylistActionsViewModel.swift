import Foundation
import Observation

/// Follow / unfollow, public-private toggle and share for one user playlist —
/// the three server actions `UserPlaylistBloc` (`lib/blocs/user_playlists/bloc.dart`)
/// exposes as `toggleFollowUserPlaylist`, `toggleUserPlaylistVisibility` and
/// (via `ShareService.sharePlaylist`) the share link. Shared by the row/page
/// "more" menu and the detail page's action row so both read the same state.
///
/// Follow state is read from `GET /library/items/ids` (`"userPlaylist:<id>"`,
/// the same key Dart's `LibraryItemsListRowChangedEvent` uses) because neither
/// single-playlist endpoint sends an `isFollowed` flag.
extension Notification.Name {
    /// A user playlist's visibility changed (optimistically, or put back);
    /// `object` is its id, `userInfo["visibility"]` the new value.
    static let userPlaylistVisibilityDidChange = Notification.Name("Hallelujah.userPlaylistVisibilityDidChange")
}

@MainActor
@Observable
final class UserPlaylistActionsViewModel {
    enum FollowOutcome: Equatable, Sendable {
        case followed(message: String)
        case unfollowed(message: String)
        case failed(message: String)
    }

    /// `showSnackBarToast` text Dart shows when a request throws.
    static var networkErrorMessage: String { String(localized: "Internet error, please check your internet") }

    let playlistID: String
    private(set) var isFollowing = false
    private(set) var visibility: String?
    private(set) var isBusy = false

    private let repository: any UserPlaylistRepository
    private let libraryRepository: any LibraryRepository
    private let shareLink: @MainActor (String) async throws -> URL
    private let onLibraryChanged: @MainActor () async -> Void
    private let logger = AppLogger(category: .content)

    init(
        playlistID: String,
        repository: any UserPlaylistRepository,
        libraryRepository: any LibraryRepository,
        shareLink: @escaping @MainActor (String) async throws -> URL,
        onLibraryChanged: @escaping @MainActor () async -> Void = {}
    ) {
        self.playlistID = playlistID
        self.repository = repository
        self.libraryRepository = libraryRepository
        self.shareLink = shareLink
        self.onLibraryChanged = onLibraryChanged
    }

    convenience init(playlistID: String, container: DependencyContainer = .current) {
        let store: LibrarySavedStore = container.resolve()
        self.init(
            playlistID: playlistID,
            repository: container.resolve(),
            libraryRepository: container.resolve(),
            shareLink: { id in try await DeepLinkService.shared.userPlaylistShareLink(id: id) },
            onLibraryChanged: { await store.refresh() }
        )
    }

    static func followKey(for id: String) -> String { "userPlaylist:\(id)" }

    /// A load's value. Ignored mid-toggle, so a slow fetch can't put back the
    /// visibility the user just changed.
    func setVisibility(_ value: String?) {
        guard !isBusy else { return }
        visibility = UserPlaylistVisibilityOverrides.shared.resolve(value, for: playlistID)
    }

    /// Whether the signed-in user follows this playlist. Non-fatal on failure
    /// (the row then reads "Add to library", as with the saved-id sync).
    func loadFollowState() async {
        guard let keys = try? await libraryRepository.fetchSavedKeys() else { return }
        isFollowing = keys.contains(Self.followKey(for: playlistID))
    }

    var isPublic: Bool { visibility == "public" }

    /// "Make Private" / "Make Public" (`custom_playlist.dart`).
    var visibilityTitle: String { isPublic ? String(localized: "Make Private") : String(localized: "Make Public") }

    /// Optimistic: the new visibility is shown everywhere at once (posted as
    /// `userPlaylistVisibilityDidChange`), then confirmed with the server's
    /// value, or put back if the call fails. Returns the toast text.
    func toggleVisibility() async -> String {
        guard !isBusy else { return "" }
        isBusy = true
        defer { isBusy = false }
        let previous = visibility
        // Unknown until the playlist loads; the server toggles either way, so
        // only its answer can be shown then.
        if let previous {
            apply(previous == "public" ? "private" : "public")
        }
        do {
            let playlist = try await repository.toggleVisibility(id: playlistID)
            if let confirmed = playlist.visibility { apply(confirmed) }
            return Self.visibilityMessage(for: visibility)
        } catch UserPlaylistRepositoryError.rejected(let message) {
            apply(previous)
            return message
        } catch {
            logger.warning("toggle visibility \(playlistID) failed: \(error)")
            apply(previous)
            return Self.networkErrorMessage
        }
    }

    private func apply(_ value: String?) {
        UserPlaylistVisibilityOverrides.shared.set(value, for: playlistID)
        guard value != visibility else { return }
        visibility = value
        NotificationCenter.default.post(
            name: .userPlaylistVisibilityDidChange,
            object: playlistID,
            userInfo: value.map { ["visibility": $0] as [AnyHashable: Any] }
        )
    }

    static func visibilityMessage(for visibility: String?) -> String {
        visibility == "public" ? String(localized: "Playlist is now public") : String(localized: "Playlist is now private")
    }

    /// Optimistic flip, reverted on failure (Dart's Realm write + revert).
    func toggleFollow() async -> FollowOutcome {
        let wasFollowing = isFollowing
        isFollowing = !wasFollowing
        isBusy = true
        defer { isBusy = false }
        do {
            let message = try await repository.toggleFollow(id: playlistID)
            await onLibraryChanged()
            return wasFollowing ? .unfollowed(message: message) : .followed(message: message)
        } catch UserPlaylistRepositoryError.rejected(let message) {
            isFollowing = wasFollowing
            return .failed(message: message)
        } catch {
            isFollowing = wasFollowing
            logger.warning("toggle follow \(playlistID) failed: \(error)")
            return .failed(message: Self.networkErrorMessage)
        }
    }

    func makeShareURL() async -> URL? {
        do {
            return try await shareLink(playlistID)
        } catch {
            logger.warning("share link \(playlistID) failed: \(error)")
            return nil
        }
    }
}
