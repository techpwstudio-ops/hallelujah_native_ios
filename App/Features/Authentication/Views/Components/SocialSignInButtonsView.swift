import SwiftUI

/// Ported from `SocialSignInButtons`
/// (`lib/widgets/authentication/social_sign_in_buttons.dart`): a centred row
/// of square icon buttons. The first button always shows the icon for the
/// method NOT currently active — phone icon while on email, mail icon while
/// on phone — and toggles `AuthenticationView`'s mode; Google and Apple
/// (`Platform.isIOS` is always true here) come after, wired to
/// `SocialAuthViewModel` (T23).
///
/// Dart sizes each button at `maxWidth * 0.2` via `LayoutBuilder`; wiring an
/// exact proportional `GeometryReader` layout isn't worth the risk without a
/// way to see it render — `buttonSize` below is a fixed, reasonable
/// approximation of that same proportion on a typical phone width, not a
/// re-derivation of the formula.
///
/// `isLoading` disables the whole row rather than animating an individual
/// button: Dart blocks the entire screen behind a global `Loader` overlay
/// for the same duration, and there's no per-icon spinner slot in this
/// layout to target just the tapped button instead.
struct SocialSignInButtonsView: View {
    let isWithEmail: Bool
    let onToggleMethod: () -> Void
    var isLoading: Bool = false
    var onGoogleSignIn: () -> Void = {}
    var onAppleSignIn: () -> Void = {}

    @Environment(\.appTheme) private var theme

    /// `_buildButton`: `maxWidth * 0.2` wide box, 8 outer padding, 1pt border,
    /// radius 8, icon 16x20 with 12 padding (so 44 tall), `.py16()` on the row.
    private static let iconHeight: CGFloat = 20 + Dimens.spacing12 * 2
    private static let rowHeight: CGFloat = iconHeight + Dimens.spacing8 * 2

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                button(proxy.size.width, icon: isWithEmail ? .phone : .mail, tint: theme.color(.textPrimary), action: onToggleMethod)
                button(proxy.size.width, icon: .google, tint: theme.color(.textPrimary), action: onGoogleSignIn)
                button(proxy.size.width, icon: .apple, tint: .white, action: onAppleSignIn)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: Self.rowHeight)
        .padding(.vertical, Spacing.md)
        .disabled(isLoading)
        .opacity(isLoading ? 0.5 : 1)
    }

    private func button(_ maxWidth: CGFloat, icon: IconToken, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            theme.icon(icon)
                .resizable()
                .scaledToFit()
                .foregroundStyle(tint)
                .frame(width: 16, height: 20)
                .padding(Dimens.spacing12)
                .frame(width: maxWidth * 0.2, height: Self.iconHeight)
                .overlay {
                    RoundedRectangle(cornerRadius: Dimens.cornerRadius, style: .continuous)
                        .strokeBorder(theme.color(.separator), lineWidth: Dimens.borderWidth)
                }
                .padding(Dimens.spacing8)
        }
        .buttonStyle(.plain)
    }
}
