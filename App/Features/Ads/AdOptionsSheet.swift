import SwiftUI
import Observation

private struct AdOptionsPresentationKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: (Bool) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Called with true when an ad's ⋮ sheet opens and false when it closes, so
    /// a surface whose ad is on a timer can hold it while the sheet is read.
    var adOptionsPresentationChanged: (Bool) -> Void {
        get { self[AdOptionsPresentationKey.self] }
        set { self[AdOptionsPresentationKey.self] = newValue }
    }
}

/// The ⋮ button behind every ad (`AdOptionsButton`,
/// `lib/widgets/ads/ad_options_button.dart`). `plain` is a bare glyph for an
/// app bar; `overlay` a translucent disc for a button on the creative itself.
struct AdOptionsButton: View {
    enum Style { case overlay, plain }

    let ad: AdCreative
    /// Returns whether the ad was actually removed (see `AdOptionsSheet`).
    var onDismissAd: (() -> Bool)?
    var style: Style = .overlay
    var size: CGFloat = 20
    var overlaySize: CGFloat = 32
    /// Present from the app shell (`adOptionsHost()`) instead of from this
    /// view. For feed ads, whose views are rebuilt/recycled while the sheet is
    /// being read — a sheet owned by the view dies with it — and for ads in the
    /// dock (mini-player strip, ad-break banner): any open sheet hides the dock
    /// (`AppNavigationCoordinator.openSheetCount`), taking this button with it.
    /// Ads inside the full-screen player keep their own sheet; the shell's host
    /// sits underneath that cover.
    var usesSharedHost = false

    @State private var isPresented = false
    @Environment(\.adOptionsPresentationChanged) private var presentationChanged

    var body: some View {
        Button {
            if usesSharedHost {
                AdOptionsPresenter.shared.present(ad: ad, onDismissAd: onDismissAd)
            } else {
                isPresented = true
            }
        } label: {
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
                .font(.system(size: size))
                .foregroundStyle(Color.white)
                .frame(width: style == .overlay ? overlaySize : 40, height: style == .overlay ? overlaySize : 40)
                .background {
                    if style == .overlay { Circle().fill(Color.black.opacity(0.45)) }
                }
                .frame(minWidth: 40, minHeight: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ad options")
        .adOptionsSheet(isPresented: $isPresented, ad: ad, onDismissAd: onDismissAd)
        .onChange(of: isPresented) { _, open in presentationChanged(open) }
        .onDisappear { if isPresented { presentationChanged(false) } }
    }
}

/// Owns the ⋮ sheet for feed ads so it outlives the ad view that opened it.
@MainActor
@Observable
final class AdOptionsPresenter {
    static let shared = AdOptionsPresenter()

    struct Request: Identifiable {
        let id = UUID()
        let ad: AdCreative
        let onDismissAd: (() -> Bool)?
    }

    var isPresented = false
    private(set) var request: Request?

    func present(ad: AdCreative, onDismissAd: (() -> Bool)?) {
        request = Request(ad: ad, onDismissAd: onDismissAd)
        isPresented = true
    }
}

private struct AdOptionsHostModifier: ViewModifier {
    @State private var presenter = AdOptionsPresenter.shared

    func body(content: Content) -> some View {
        content.appSheet(isPresented: $presenter.isPresented, detents: [.height(380), .large]) {
            if let request = presenter.request {
                AdOptionsSheet(
                    ad: request.ad,
                    onDismissAd: request.onDismissAd,
                    close: { presenter.isPresented = false }
                )
            }
        }
    }
}

extension View {
    /// Apply once on the signed-in shell; presents sheets requested by
    /// `AdOptionsButton(usesSharedHost: true)`.
    func adOptionsHost() -> some View { modifier(AdOptionsHostModifier()) }

    /// `showAdOptionsSheet`.
    func adOptionsSheet(isPresented: Binding<Bool>, ad: AdCreative, onDismissAd: (() -> Bool)?) -> some View {
        appSheet(isPresented: isPresented, detents: [.height(380), .large]) {
            AdOptionsSheet(ad: ad, onDismissAd: onDismissAd, close: { isPresented.wrappedValue = false })
        }
    }
}

/// `showAdOptionsSheet` (`lib/sheets/ads/ad_options_sheet.dart`): header
/// "Tell us what you think", Interested / Not interested › / Report ad › /
/// Close ad, a divider, then "Go ad-free". The two chevron rows swap this
/// sheet for the reason list (picking a reason submits and closes).
struct AdOptionsSheet: View {
    let ad: AdCreative
    var onDismissAd: (() -> Bool)?
    let close: () -> Void

    private enum Page: Equatable { case menu, reasons(AdFeedbackKind) }

    @State private var page: Page = .menu
    @State private var ads: AdsRepository = DependencyContainer.current.resolve()
    @Environment(AppNavigationCoordinator.self) private var coordinator
    @Environment(\.toastCenter) private var toastCenter
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            switch page {
            case .menu: menu
            case let .reasons(kind): reasons(kind)
            }
        }
    }

    // MARK: Menu

    private var menu: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Tell us what you think")
            divider
            Spacer().frame(height: Dimens.spacing8)
            SongMenuRow(systemImage: "hand.thumbsup", title: "Interested") {
                close()
                ads.submitFeedback(ad: ad, kind: .interested)
                toastCenter.show("Thanks \u{2014} we'll show you more like this")
            }
            SongMenuRow(systemImage: "hand.thumbsdown", title: "Not interested", action: { page = .reasons(.notInterested) }) { chevron }
            SongMenuRow(systemImage: "exclamationmark.circle", title: "Report ad", action: { page = .reasons(.report) }) { chevron }
            SongMenuRow(systemImage: "xmark", title: "Close ad") {
                close()
                ads.submitFeedback(ad: ad, kind: .close)
                // A dismissed ad needs no confirmation — it visibly went away.
                if !(onDismissAd?() ?? false) {
                    toastCenter.show("Your music will continue after this ad")
                }
            }
            divider
            SongMenuRow(systemImage: "crown", title: "Go ad-free") {
                close()
                coordinator.push(.subscriptionPlans)
            }
            Spacer().frame(height: Dimens.spacing16)
        }
        .padding(.horizontal, Dimens.spacing16)
    }

    // MARK: Reasons

    private func reasons(_ kind: AdFeedbackKind) -> some View {
        let isReport = kind == .report
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(isReport ? "What's wrong with this ad?" : "Why don't you want to see this?")
                divider
                Spacer().frame(height: Dimens.spacing8)
                ForEach(AdFeedbackReason.reasons(for: kind), id: \.self) { reason in
                    Button {
                        close()
                        ads.submitFeedback(ad: ad, kind: kind, reason: reason.rawValue)
                        _ = onDismissAd?()
                        toastCenter.show(isReport ? "Thanks for reporting. We'll take a look." : "You'll see less of this ad")
                    } label: {
                        Text(reason.label)
                            .typography(Typography.titleMedium)
                            .foregroundStyle(theme.color(.textPrimary))
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer().frame(height: Dimens.spacing16)
            }
            .padding(.horizontal, Dimens.spacing16)
        }
    }

    // MARK: Pieces

    private func header(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .typography(Typography.titleMedium)
            .fontWeight(.bold)
            .foregroundStyle(theme.color(.textPrimary))
            .padding(.bottom, Dimens.spacing16)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.5))
    }
}
