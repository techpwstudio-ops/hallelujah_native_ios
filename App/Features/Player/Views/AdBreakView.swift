import AVKit
import SwiftUI

/// T69 — the ad-break surface, rendered inline inside `FullPlayerView` when
/// `AdPacingController.isAdBreak` is true (see that file's updated doc
/// comment on where this hooks in) rather than as a new
/// `FullScreenDestination` case — `AppNavigationCoordinator`'s own doc
/// comment on `.player` already anticipated an ad break would be presented
/// exactly this way.
///
/// Ports `AdBreakScreen` (`lib/ads/ad_break_screen.dart`), scoped to its
/// player-ad-break surface only. NOT ported: the home-feed banner / dashboard
/// mini-banner placements and the linger-after-dismiss companion banner —
/// none of those have a native host screen yet (see `AdPacingController`'s
/// own doc comment on the same cut).
struct AdBreakView: View {
    let pacing: AdPacingController

    @Environment(\.appTheme) private var theme
    @Environment(AppNavigationCoordinator.self) private var coordinator

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer(minLength: 0)

            creative

            captions

            progressBar
                .padding(.top, Spacing.sm)

            pauseButton

            ctaButton

            Spacer(minLength: 0)

            skipControl
                .padding(.bottom, Spacing.xl)
                .frame(height: Spacing.xxl)
        }
        .padding(.top, Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.color(.backgroundPrimary).ignoresSafeArea())
    }

    @ViewBuilder
    private var creative: some View {
        if let ad = pacing.currentAd {
            if ad.assetType == "reel_video", let player = pacing.adPlayer {
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                    .padding(.horizontal, Spacing.md)
            } else {
                companionImage(for: ad)
            }
        }
    }

    /// The audio-ad companion visual: `companionImageUrl`, falling back to
    /// `squareImageUrl` — the same fallback order `AdCreative`'s own doc
    /// comment on `squareImageUrl` names ("fallback avatar when
    /// `advertiserLogoUrl` is null") generalized to this slot too, since both
    /// fields are already-signed URLs with the same "load directly" rule.
    @ViewBuilder
    private func companionImage(for ad: AdCreative) -> some View {
        let urlString = ad.companionImageUrl ?? ad.squareImageUrl
        AsyncImage(url: urlString.flatMap(URL.init(string:))) { image in
            image.resizable().aspectRatio(contentMode: .fit)
        } placeholder: {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(theme.color(.backgroundSecondary))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .padding(.horizontal, Spacing.md)
    }

    @ViewBuilder
    private var captions: some View {
        if let ad = pacing.currentAd {
            VStack(spacing: Spacing.sm) {
                advertiserRow(for: ad)
                if let headline = ad.headline {
                    Text(headline)
                        .typography(Typography.titleLarge)
                        .foregroundStyle(theme.color(.textPrimary))
                        .multilineTextAlignment(.center)
                }
                if let bodyText = ad.bodyText {
                    Text(bodyText)
                        .typography(Typography.bodyMedium)
                        .foregroundStyle(theme.color(.textSecondary))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
        }
    }

    @ViewBuilder
    private func advertiserRow(for ad: AdCreative) -> some View {
        if let advertiserName = ad.advertiserName {
            HStack(spacing: Spacing.sm) {
                let logo = ad.advertiserLogoUrl ?? ad.squareImageUrl
                AsyncImage(url: logo.flatMap(URL.init(string:))) { image in
                    image.resizable()
                } placeholder: {
                    Circle().fill(theme.color(.backgroundSecondary))
                }
                .frame(width: 24, height: 24)
                .clipShape(Circle())

                Text(advertiserName)
                    .typography(Typography.labelMedium)
                    .foregroundStyle(theme.color(.textSecondary))
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            let fraction = pacing.adTotalDuration > 0
                ? min(pacing.adPosition / pacing.adTotalDuration, 1)
                : 0
            ZStack(alignment: .leading) {
                Capsule().fill(theme.color(.border))
                Capsule()
                    .fill(theme.color(.textPrimary))
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 3)
        .padding(.horizontal, Spacing.lg)
    }

    /// `AdBreakScreen`'s own play/pause affordance — non-interactive
    /// progress bar above it, same split Dart's screen uses (the seek bar
    /// there isn't scrubbable either).
    private var pauseButton: some View {
        Button(action: pacing.togglePause) {
            theme.icon(pacing.isAdPaused ? .play : .pause)
                .font(.system(size: 22))
                .foregroundStyle(theme.color(.textPrimary))
                .frame(width: Spacing.minTapTarget, height: Spacing.minTapTarget)
        }
        .buttonStyle(.plain)
        .padding(.top, Spacing.sm)
    }

    @ViewBuilder
    private var ctaButton: some View {
        if let ctaLabel = pacing.currentAd?.ctaLabel {
            AppButton(label: ctaLabel) {
                pacing.openAction(coordinator: coordinator)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
        }
    }

    /// `adSkipUnlockAt` nil means an unskippable creative — no control at
    /// all, matching Dart (`clearAdSkipUnlockAt: skipAfter == null`). A
    /// `TimelineView` drives both the countdown and the moment it flips to
    /// a real Skip button, since `AdPacingController.canSkip` is a
    /// wall-clock computed value `@Observable` has no stored property to
    /// invalidate on.
    @ViewBuilder
    private var skipControl: some View {
        if let unlocksAt = pacing.adSkipUnlocksAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if context.date >= unlocksAt {
                    Button("Skip", action: pacing.skip)
                        .typography(Typography.labelLarge)
                        .foregroundStyle(theme.color(.textPrimary))
                } else {
                    let remaining = max(0, Int(unlocksAt.timeIntervalSince(context.date).rounded(.up)))
                    Text("Skip in \(remaining)s")
                        .typography(Typography.labelLarge)
                        .foregroundStyle(theme.color(.textSecondary))
                }
            }
        }
    }
}
