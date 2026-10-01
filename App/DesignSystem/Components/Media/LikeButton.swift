import SwiftUI

/// Circular favorite/follow toggle — native port of `FavouriteCreatorButton`
/// (`lib/widgets/creator/favourite_creator_button.dart`): a 40×40 circle
/// holding a 24pt icon (`Icons.favorite`/`Icons.favorite_border` →
/// `.favoriteFilled`/`.favorite`, same single ambient color either way —
/// Dart's `Icon(...)` there passes no `color:` at all, so the filled state
/// is not tinted red or anything else, only the glyph shape changes), cross-
/// fading against a loading spinner with a 250ms scale+fade transition
/// (`AnimatedSwitcher`, `switchInCurve: easeOutBack`, `switchOutCurve:
/// easeIn` — approximated with a single spring since SwiftUI's built-in
/// `.transition`/`.animation` pair doesn't expose separate in/out curves the
/// way `AnimatedSwitcher` does).
///
/// The background upgrades Dart's flat `Colors.white.withOpacity(shadowOpacity)`
/// fill (`shadowOpacity = 0.06`, `lib/theme/values.dart`) to a real
/// `GlassSurface` circle — the same "sheets sit outside D10 pixel-parity,
/// glass is the improvement" reasoning `AppSheetContainer` already used
/// (see its own doc comment): this is a decorative chip on a content
/// screen, not one of the pixel-parity-mandated splash/auth screens.
///
/// Just the icon-toggle chip: the follower-count `Text` sitting next to it
/// in the Dart widget is caller-specific business content composed by
/// whatever screen uses this, not part of the reusable primitive.
struct LikeButton: View {
    var isLiked: Bool
    var isLoading: Bool = false
    var action: () -> Void

    @Environment(\.appTheme) private var theme

    private static let diameter: CGFloat = 40
    private static let iconSize: CGFloat = 24

    var body: some View {
        GlassSurface(.regular, in: Circle()) {
            ZStack {
                if isLoading {
                    // Dart's `ballScaleRipple` spinner is two-color
                    // (`[Colors.white, Colors.cyan]`); SwiftUI's built-in
                    // `ProgressView` has no matching multi-color ripple
                    // style, so this uses the same single-tint substitution
                    // `LoadingStateView` already established in T12.
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(theme.color(.textPrimary))
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Button(action: action) {
                        theme.icon(isLiked ? .favoriteFilled : .favorite)
                            .font(.system(size: Self.iconSize))
                            .foregroundStyle(theme.color(.textPrimary))
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: Self.diameter, height: Self.diameter)
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isLoading)
    }
}
