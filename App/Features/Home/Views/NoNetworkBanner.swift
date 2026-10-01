import SwiftUI

/// Ports `NoNetworkBanner` (`lib/widgets/ui/no_network_banner.dart`) — a
/// full-width offline banner. Its one real Dart mount point is
/// `home_screen.dart`, not a global app-shell overlay, so this is wired into
/// the Home tab specifically (`AppShellView`'s `TabRootView`), not
/// `AppShellView` itself.
///
/// Colors are literal, not `ColorToken`s: Dart hardcodes this banner's
/// palette (`0xFFEF5350` / `0xFF1C0808`) independent of the app's theme,
/// same reasoning as the splash screen's literal `Color.black` (T15) —
/// `statusError` (`Assets.xcassets`, `0xBA0319`/`0xCA4D53`) is a different
/// red and would misrepresent this specific banner's real color.
///
/// Dart's `AnimatedSize` (height 0 -> natural, 280ms `easeInOut`) is ported
/// as an insert/remove transition with the same duration/curve
/// (`MotionCurve.offlineBanner`) rather than a literal height animation —
/// behaviorally equivalent, and consistent with how T17 already treats
/// Dart's `AnimationController`-driven motion (match duration/curve exactly,
/// let SwiftUI's own mechanism drive the interpolation). `SafeArea(bottom:
/// false)` has no native counterpart to port: this view never ignores the
/// safe area in the first place, so there is no extra inset to opt out of.
struct NoNetworkBanner: View {
    @Environment(NetworkStatusStore.self) private var networkStatus
    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.appTheme) private var theme

    /// Resets automatically once back online, so the banner reappears on
    /// the next offline period — mirrors `_NoNetworkBannerState`'s
    /// `listener` clearing `_dismissed` on `!isOffline`.
    @State private var isDismissed = false

    private static let red = Color(red: 0xEF / 255, green: 0x53 / 255, blue: 0x50 / 255)
    private static let background = Color(red: 0x1C / 255, green: 0x08 / 255, blue: 0x08 / 255)

    private var isShown: Bool { networkStatus.isOffline && !isDismissed }

    var body: some View {
        Group {
            if isShown {
                content
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(MotionCurve.offlineBanner, value: isShown)
        .onChange(of: networkStatus.isOffline) { _, isOffline in
            if !isOffline { isDismissed = false }
        }
    }

    private var content: some View {
        HStack(spacing: 0) {
            Button {
                coordinator.push(.downloads(type: "music"), in: .home)
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Self.red.opacity(0.12))
                            .frame(width: 29, height: 29)
                        theme.icon(.noNetwork)
                            .font(.system(size: 15))
                            .foregroundStyle(Self.red)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("offline.banner.title")
                            .font(.system(size: 13, weight: .semibold))
                            .tracking(0.1)
                            .foregroundStyle(.white)
                        Text("offline.banner.subtitle")
                            .font(.system(size: 11))
                            .tracking(0.1)
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Spacer(minLength: 0)

                    theme.icon(.chevronForward)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.25))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                isDismissed = true
            } label: {
                theme.icon(.close)
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Self.background)
        .overlay(alignment: .leading) {
            Rectangle().fill(Self.red).frame(width: 3)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Self.red.opacity(0.18)).frame(height: 1)
        }
    }
}

#Preview {
    NoNetworkBanner()
        .environment(AppNavigationCoordinator())
        .environment(NetworkStatusStore())
        .environment(\.appTheme, .standard)
}
