import SwiftUI

/// Scale-on-press (`ScaleOnTap`, 0.95 over 150ms ease-out) for the Premium
/// button.
private struct HomeScaleOnPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// The Home profile row (`home_screen.dart`'s first sliver): a 28pt avatar in
/// a 1pt white24 ring, "Hi <first name>" (titleMedium — "Hi" white54, the
/// name w700), the Premium pill when subscriptions are enabled, and the 28pt
/// app logo in a 30pt box. Padded 16 horizontally, 16 above and 12 below.
/// Tapping the avatar/name opens Settings; the pill opens the plans screen.
struct HomeHeaderView: View {
    @Environment(AppNavigationCoordinator.self) private var coordinator

    @State private var currentUserStore: CurrentUserStore = DependencyContainer.current.resolve()
    @State private var premiumGate: PremiumGate = DependencyContainer.current.resolve()
    @State private var user: User?
    @State private var isPremium = false

    private static let freeBorder = [
        Color(red: 0xE6 / 255, green: 0xE6 / 255, blue: 0xE6 / 255),
        Color(red: 0xBF / 255, green: 0xBF / 255, blue: 0xBF / 255),
        Color(red: 0x8F / 255, green: 0x8F / 255, blue: 0x8F / 255),
        Color(red: 0xBF / 255, green: 0xBF / 255, blue: 0xBF / 255),
        Color(red: 0xE6 / 255, green: 0xE6 / 255, blue: 0xE6 / 255),
    ]
    private static let freeBackground = [
        Color(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3A / 255),
        Color(red: 0x2F / 255, green: 0x2F / 255, blue: 0x2F / 255),
    ]
    private static let premiumBorder = [
        Color(red: 0xFF / 255, green: 0xE7 / 255, blue: 0xA3 / 255),
        Color(red: 0xFF / 255, green: 0xC8 / 255, blue: 0x57 / 255),
        Color(red: 0xE0 / 255, green: 0xA0 / 255, blue: 0x1F / 255),
        Color(red: 0xFF / 255, green: 0xC8 / 255, blue: 0x57 / 255),
        Color(red: 0xFF / 255, green: 0xE7 / 255, blue: 0xA3 / 255),
    ]
    private static let premiumBackground = [
        Color(red: 0x3A / 255, green: 0x2A / 255, blue: 0x05 / 255),
        Color(red: 0x6B / 255, green: 0x4A / 255, blue: 0x0F / 255),
    ]
    private static let premiumText = Color(red: 0xFF / 255, green: 0xC8 / 255, blue: 0x57 / 255)

    private var firstName: String {
        let name = user?.firstName?.homeCapitalized ?? ""
        return name.isEmpty ? "User" : name
    }

    var body: some View {
        HStack(spacing: 0) {
            Button { coordinator.push(.settings) } label: {
                HStack(spacing: Dimens.spacing8) {
                    avatar
                    greeting
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if RemoteSettings.current.showSubscription {
                Button { coordinator.push(.subscriptionPlans) } label: { premiumPill }
                    .buttonStyle(HomeScaleOnPressStyle())
            }

            Color.clear.frame(width: Dimens.spacing8)

            Image("AppLogo")
                .resizable()
                .scaledToFill()
                .frame(width: Dimens.profileImageSize, height: Dimens.profileImageSize)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .circular))
                .frame(width: Dimens.logoSize, height: Dimens.logoSize)
        }
        .padding(.horizontal, Dimens.screenPaddingAll * 2)
        .padding(.top, Dimens.spacing16)
        .padding(.bottom, Dimens.verticalSpacing)
        .task {
            user = await currentUserStore.user
            isPremium = await premiumGate.hasPremium
        }
    }

    /// "Hi " (white54) + the first name (w700, white), both titleMedium.
    private var greeting: some View {
        let hi = Text("Hi ").foregroundStyle(HomeColors.white50)
        let name = Text(firstName).fontWeight(.bold).foregroundStyle(Color.white)
        let combined: Text = hi + name
        return combined
            .typography(Typography.titleMedium)
            .lineLimit(1)
    }

    /// `LoadImage(path: image ?? defaultThumbnailUrl(name))` in a 28pt circle.
    /// With no stored image Dart asks the server for a letter tile; with no
    /// such URL available natively, the same tile is drawn locally.
    @ViewBuilder
    private var avatar: some View {
        let size = Dimens.profileImageSize
        Group {
            if let image = user?.image, !image.isEmpty {
                ArtworkView(
                    url: HomeArt.url(image, user?.imageVariants, .sm),
                    width: size,
                    height: size,
                    cornerRadius: size
                )
            } else {
                ZStack {
                    Circle().fill(HomeColors.darkFill)
                    Text(String(firstName.prefix(1)).uppercased())
                        .font(.custom(Typography.fontFamily, size: 14).weight(.semibold))
                        .foregroundStyle(Color.white)
                }
                .frame(width: size, height: size)
            }
        }
        .padding(Dimens.spacing2)
        .overlay(Circle().strokeBorder(HomeColors.white24, lineWidth: Dimens.borderWidth))
    }

    /// `PremiumButton` — a 28pt pill: a 1.5pt gradient ring (radius 16) around
    /// a gradient body (radius 14), "Explore Premium" / "Premium" in labelLarge
    /// w700 with 0.3 tracking.
    private var premiumPill: some View {
        let colors = isPremium ? Self.premiumBackground : Self.freeBackground
        let border = isPremium ? Self.premiumBorder : Self.freeBorder
        let textColor = isPremium ? Self.premiumText : Color.white
        return Text(isPremium ? "Premium" : "Explore Premium")
            .typography(Typography.labelLarge)
            .fontWeight(.bold)
            .tracking(0.3)
            .foregroundStyle(textColor)
            .padding(.horizontal, Dimens.horizontalGapMedium)
            .frame(maxHeight: .infinity)
            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 14, style: .circular)
            )
            .padding(Dimens.premiumButtonBorderPadding)
            .background(
                LinearGradient(colors: border, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 16, style: .circular)
            )
            .frame(height: Dimens.premiumButtonHeight)
    }
}

/// `_HomeHeaderDelegate` / `HomeAppBottomBar` — the pinned All / Music /
/// Podcast switcher: a 44pt bar over black with a faint drop shadow, three
/// equal 35pt buttons (radius 8; selected white with black text, otherwise
/// 0xFF1D1D1D with white text; 14pt w500) inset 12 from the screen edge.
struct HomeSongTypeBar: View {
    @Binding var selection: HomeContentType

    private struct Item: Identifiable {
        let type: HomeContentType
        let name: String
        var id: String { type.rawValue }
    }

    private let items = [
        Item(type: .all, name: "All"),
        Item(type: .music, name: "Music"),
        Item(type: .episode, name: "Podcast"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                button(item)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Dimens.screenPaddingAll * 1.5)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(
            HomeColors.background
                .shadow(color: Color.black.opacity(0.45), radius: 2, x: 0, y: 2)
        )
    }

    private func button(_ item: Item) -> some View {
        let isSelected = selection == item.type
        return Button {
            selection = item.type
        } label: {
            Text(item.name)
                .font(.custom(Typography.fontFamily, size: 14, relativeTo: .body).weight(.medium))
                .foregroundStyle(isSelected ? Color.black : Color.white)
                .padding(.horizontal, Dimens.spacing8)
                .frame(maxWidth: .infinity, minHeight: 35, maxHeight: 35)
                .frame(minWidth: 90)
                .background(
                    isSelected ? Color.white : HomeColors.fill,
                    in: RoundedRectangle(cornerRadius: 8, style: .circular)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
