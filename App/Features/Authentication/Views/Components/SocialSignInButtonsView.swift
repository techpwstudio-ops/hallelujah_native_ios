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

    /// `_buildButton`: `maxWidth * 0.2` wide box, 8 outer padding, 1pt border,
    /// radius 8, icon with 12 padding plus the 1pt border, `.py16()` on the row.
    /// Dart gives the SVG a 16x20 box but the icons are square, so they draw
    /// 16x16 (`BoxFit.contain`) — the button is 42 tall, not 46.
    private static let iconSize: CGFloat = 16
    private static let iconHeight: CGFloat = iconSize + Dimens.spacing12 * 2 + Dimens.borderWidth * 2
    private static let rowHeight: CGFloat = iconHeight + Dimens.spacing8 * 2

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                button(proxy.size.width, icon: isWithEmail ? "AuthPhone" : "AuthMail", action: onToggleMethod)
                button(proxy.size.width, icon: "AuthGoogle", action: onGoogleSignIn)
                button(proxy.size.width, icon: "AuthApple", action: onAppleSignIn)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: Self.rowHeight)
        .padding(.vertical, Spacing.md)
        .disabled(isLoading)
        .opacity(isLoading ? 0.5 : 1)
    }

    /// `icon` is an `AuthIcons` asset — Dart's own `assets/icons/*.svg`, so the
    /// Google "G" keeps its brand colours while phone/mail/Apple are white
    /// templates.
    private func button(_ maxWidth: CGFloat, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .padding(Dimens.spacing12)
                .frame(width: maxWidth * 0.2, height: Self.iconHeight)
                .overlay {
                    RoundedRectangle(cornerRadius: Dimens.cornerRadius, style: .continuous)
                        .strokeBorder(.white, lineWidth: Dimens.borderWidth)
                }
                .padding(Dimens.spacing8)
        }
        .buttonStyle(.plain)
    }
}
