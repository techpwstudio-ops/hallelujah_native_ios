import AVKit
import SwiftUI

/// Ports `AdBreakScreen` (`lib/views/home/ad_break_screen.dart`), rendered
/// inline by `FullPlayerView` while `AdPacingController.isAdBreak` is true.
/// Black screen; the creative decides the layout:
///   * audio ad — app bar ("Your music will continue after the break", 56pt),
///     the picture centred in the leftover space at the largest box of its own
///     aspect ratio (the player's full-width square), then the control panel;
///   * video ad (`reel_video`) — the video fills the screen (cover) and the
///     same chrome floats over it on scrims (top black @ 65%, bottom @ 92%).
/// The control panel keeps `AudioPlayerScreen`'s metrics (20 side padding,
/// 20 top, 8 bottom; 16 / 20 / 24 gaps; 58pt disc): advertiser row with the
/// Skip chip, a non-seekable 6pt scrubber, the transport row (thumbs, inert
/// prev/next, play-pause), and the footer line + CTA pill.
///
/// Not ported: the two-back-presses escape hatch, the wide (16:9) picture variant (the native
/// `AdCreative` carries no `wideImageUrl`). Like / dislike persist through
/// `AdsRepository.react`.
struct AdBreakView: View {
    let pacing: AdPacingController

    @Environment(AppNavigationCoordinator.self) private var coordinator

    var body: some View {
        ZStack {
            PlayerStyle.black.ignoresSafeArea()
            if let ad = pacing.currentAd {
                if ad.assetType == "reel_video" {
                    VideoAdBreak(pacing: pacing, ad: ad, coordinator: coordinator)
                } else {
                    AudioAdBreak(pacing: pacing, ad: ad, coordinator: coordinator)
                }
            }
        }
    }
}

// MARK: - Layouts

private struct AudioAdBreak: View {
    let pacing: AdPacingController
    let ad: AdCreative
    let coordinator: AppNavigationCoordinator

    var body: some View {
        VStack(spacing: 0) {
            AdBreakAppBar(pacing: pacing, ad: ad)
            AdBreakArtwork(ad: ad)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            AdBreakControlPanel(pacing: pacing, ad: ad, coordinator: coordinator)
        }
    }
}

private struct VideoAdBreak: View {
    let pacing: AdPacingController
    let ad: AdCreative
    let coordinator: AppNavigationCoordinator

    var body: some View {
        ZStack {
            Group {
                if let player = pacing.adPlayer {
                    AdVideoSurface(player: player)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(PlayerStyle.whiteAlpha(0.54))
                        .scaleEffect(1.4)
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                AdBreakAppBar(pacing: pacing, ad: ad)
                    .background(scrim(fromTop: true))
                Spacer(minLength: 0)
                AdBreakControlPanel(pacing: pacing, ad: ad, coordinator: coordinator)
                    .background(scrim(fromTop: false))
            }
        }
    }

    /// `_Scrim`: black @ 65% (top) / 92% (bottom) fading to clear.
    private func scrim(fromTop: Bool) -> some View {
        LinearGradient(
            colors: [PlayerStyle.black.opacity(fromTop ? 0.65 : 0.92), PlayerStyle.black.opacity(0)],
            startPoint: fromTop ? .top : .bottom,
            endPoint: fromTop ? .bottom : .top
        )
        .ignoresSafeArea()
    }
}

/// Cover-fit, controls-free video surface (`FittedBox(fit: BoxFit.cover)`).
private struct AdVideoSurface: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}

// MARK: - App bar

/// `_AdBreakAppBar`: no back button; a 44pt leading space keeps the centred
/// `bodySmall` white @ 70% line (max 2 lines) where it always sat.
private struct AdBreakAppBar: View {
    let pacing: AdPacingController
    let ad: AdCreative

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 44)
            Text("Your music will continue after the break")
                .typography(Typography.bodySmall)
                .foregroundStyle(PlayerStyle.whiteAlpha(0.7))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
            // `AdOptionsButton(style: plain, size: 24, onDismissAd:
            // dismissAdBreakIfSkippable)` — respects the creative's own skip
            // lock instead of handing out a second, hidden Skip.
            AdOptionsButton(ad: ad, onDismissAd: {
                guard pacing.canSkip else { return false }
                pacing.skip()
                return true
            }, style: .plain, size: 24)
            .padding(.trailing, 4)
        }
        .frame(height: PlayerStyle.toolbarHeight)
    }
}

// MARK: - Artwork

/// `_AdBreakArtwork`: the picture whole, in its own shape, at the largest box
/// that fits; no picture (or a failed load) is the campaign glyph on
/// `darkSurface`.
private struct AdBreakArtwork: View {
    let ad: AdCreative

    private var urlString: String? { ad.companionImageUrl ?? ad.squareImageUrl }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                if let urlString, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        case .failure:
                            glyph
                        default:
                            PlayerStyle.darkSurface
                        }
                    }
                } else {
                    glyph
                }
            }
            .frame(width: side, height: side)
            .clipped()
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private var glyph: some View {
        ZStack {
            PlayerStyle.darkSurface
            Image(systemName: "megaphone")
                .font(.system(size: 56))
                .foregroundStyle(PlayerStyle.white)
        }
    }
}

// MARK: - Control panel

private struct AdBreakControlPanel: View {
    let pacing: AdPacingController
    let ad: AdCreative
    let coordinator: AppNavigationCoordinator

    @State private var reaction: Reaction?
    private let ads: AdsRepository = DependencyContainer.current.resolve()

    private typealias Reaction = AdReaction

    private var hasCTA: Bool { ad.action != nil || ad.clickUrl != nil }

    var body: some View {
        VStack(spacing: 0) {
            advertiserRow
            PlayerSeekBar(
                position: pacing.adPosition,
                duration: pacing.adTotalDuration,
                barHeight: PlayerStyle.seekBarHeight,
                isInteractive: false
            )
            .padding(.top, 16)
            transport
                .padding(.top, 20)
            footer
                .padding(.top, 24)
        }
        .padding(.horizontal, PlayerStyle.pageSidePadding)
        .padding(.top, PlayerStyle.pageSidePadding)
        .padding(.bottom, 8 + 12)
        // A different ad in the slot starts from what the repository holds for it.
        .task(id: ad.impressionToken) { reaction = ads.reaction(for: ad) }
    }

    // `_AdBreakAdvertiserRow`

    private var advertiserRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(ad.headline?.isEmpty == false ? (ad.headline ?? "") : String(localized: "Advertisement"))
                    .typography(PlayerStyle.titleMediumBold)
                    .foregroundStyle(PlayerStyle.white)
                    .lineLimit(1)
                Text("Advertisement · 1 of 1")
                    .typography(Typography.bodyMedium)
                    .foregroundStyle(PlayerStyle.whiteAlpha(0.7))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            skipChip
        }
    }

    /// `_AdBreakSkipButton`: absent for an unskippable creative; while the wait
    /// runs it shows the seconds left in a chip, then becomes live.
    @ViewBuilder
    private var skipChip: some View {
        if let unlockAt = pacing.adSkipUnlocksAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let canSkip = context.date >= unlockAt
                let remaining = canSkip ? 0 : Int(unlockAt.timeIntervalSince(context.date)) + 1
                let tint = canSkip ? PlayerStyle.black : PlayerStyle.greyMuted
                Button {
                    if canSkip { pacing.skip() }
                } label: {
                    HStack(spacing: 0) {
                        Text("Skip")
                            .typography(Typography.titleSmall)
                            .foregroundStyle(tint)
                        if !canSkip {
                            Text("\(remaining)")
                                .typography(Typography.labelMedium)
                                .foregroundStyle(PlayerStyle.black)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(PlayerStyle.greySubtle))
                                .padding(.leading, 6)
                        }
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(tint)
                            .padding(.leading, 4)
                    }
                    .padding(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 10))
                    .background(Capsule().fill(PlayerStyle.white))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSkip)
            }
        }
    }

    // `_AdBreakTransport`: thumbs where shuffle / loop sit, inert prev / next,
    // the live play-pause disc.

    private var transport: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            thumb(.dislike)
            Spacer(minLength: 0)
            inertGlyph("backward.end.fill")
            Spacer(minLength: 0)
            Button(action: pacing.togglePause) {
                PlayerPlayPauseDisc(isPlaying: !pacing.isAdPaused, isLoading: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(pacing.isAdPaused ? "Play" : "Pause")
            Spacer(minLength: 0)
            inertGlyph("forward.end.fill")
            Spacer(minLength: 0)
            thumb(.like)
            Spacer(minLength: 0)
        }
    }

    private func inertGlyph(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: PlayerStyle.seekGlyphSize))
            .foregroundStyle(PlayerStyle.whiteAlpha(0.24))
            .padding(PlayerStyle.controlGlyphPadding)
    }

    /// `AdReactionThumb`: filled white when lit, outlined white @ 70% idle;
    /// tapping the lit thumb takes it back (`nextReaction`).
    private func thumb(_ kind: Reaction) -> some View {
        let isLike = kind == .like
        let selected = reaction == kind
        let name = isLike
            ? (selected ? "hand.thumbsup.fill" : "hand.thumbsup")
            : (selected ? "hand.thumbsdown.fill" : "hand.thumbsdown")
        return Button {
            let next = AdReaction.next(current: reaction, tapped: kind)
            reaction = next
            ads.react(to: ad, next)
        } label: {
            Image(systemName: name)
                .font(.system(size: 24))
                .foregroundStyle(selected ? PlayerStyle.white : PlayerStyle.whiteAlpha(0.7))
                .padding(PlayerStyle.controlGlyphPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLike ? "Like this ad" : "Dislike this ad")
    }

    // `_AdBreakFooter`

    private var footer: some View {
        let line = ad.headline?.isEmpty == false ? (ad.headline ?? "") : (ad.bodyText ?? "")
        return HStack(spacing: 12) {
            Text(line)
                .typography(Typography.bodyMedium)
                .foregroundStyle(PlayerStyle.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                if hasCTA { pacing.openAction(coordinator: coordinator) }
            } label: {
                Text(ad.ctaLabel?.isEmpty == false ? (ad.ctaLabel ?? String(localized: "More Info")) : String(localized: "More Info"))
                    .typography(Typography.titleSmall)
                    .foregroundStyle(hasCTA ? PlayerStyle.black : PlayerStyle.whiteAlpha(0.54))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(hasCTA ? PlayerStyle.white : PlayerStyle.whiteAlpha(0.24)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!hasCTA)
        }
    }
}
