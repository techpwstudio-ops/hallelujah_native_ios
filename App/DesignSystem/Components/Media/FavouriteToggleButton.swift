import SwiftUI

/// Flat song-favorite heart — native port of `FavouriteButton`/`FavoriteIcon`
/// (`lib/widgets/icons.dart`): unlike `LikeButton` (the circular
/// `GlassSurface` chip that ports `FavouriteCreatorButton`), Dart's song
/// widget is just an `Icon` (`Icons.favorite`/`Icons.favorite_border`) inside
/// an `InkWell`'s tap padding — no background shape, no loading-spinner
/// cross-fade. `color` defaults to `nil` here to mean "ambient
/// `textPrimary`," matching Dart's own `color = Colors.white` default
/// (`icons.dart`'s `FavouriteButton{song, color = Colors.white, size = 24}`).
///
/// Deliberately presentational only — no repository call inside. Both call
/// sites (mini player, full player) need the same optimistic
/// toggle-then-revert-on-failure effect against `AudioEngine.currentSong`,
/// but each owns its own copy of that logic rather than this view calling a
/// repository directly, so `action` is fully owned by the caller; this
/// view's only job is the tap target, the glyph, and guarding against a
/// double-tap firing the action twice while the first call is still in
/// flight. Not used by `FavouriteSongsView`'s list — that screen has no
/// per-row heart at all (see `FavouriteSongsViewModel`'s doc comment for why
/// that's a deliberate, grounded scope match, not an oversight).
struct FavouriteToggleButton: View {
    var isFavorited: Bool
    var size: CGFloat = 24
    var color: Color? = nil
    var action: () async -> Void

    @Environment(\.appTheme) private var theme
    @State private var isToggling = false

    var body: some View {
        Button {
            guard !isToggling else { return }
            isToggling = true
            Task {
                await action()
                isToggling = false
            }
        } label: {
            theme.icon(isFavorited ? .favoriteFilled : .favorite, size: size)
                .foregroundStyle(color ?? theme.color(.textPrimary))
        }
        .buttonStyle(.plain)
    }
}
