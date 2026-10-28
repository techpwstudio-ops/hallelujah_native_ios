import AVFoundation
import SwiftUI

/// Ports `AdBreakScreen` (`lib/views/home/ad_break_screen.dart`), rendered
/// inline by `FullPlayerView` while `AdPacingController.isAdBreak` is true.
/// Black screen; the creative decides the layout:
///   * audio ad — app bar ("Your music will continue after the break", 56pt),
///     the picture centred in the leftover space at the largest box of its own
///     aspect ratio (the player's full-width square), then the control panel;
///   * video ad (`reel_video`) — the video on black and only what a reel has
///     over it (`ReelAdBreak`): a "Sponsored" tag, the Skip chip when the
///     creative has one, the ⋮ menu, a heart, and the call to action. No
///     scrubber, transport, advertiser rows or scrim — a reel is a picture to
///     look at, not a track to control. The video is the screen's width and its
///     own height, centred (`reelVideoSize`), never cropped; a tap pauses it.
/// The audio control panel keeps `AudioPlayerScreen`'s metrics (20 side
/// padding, 20 top, 8 bottom; 16 / 20 / 24 gaps; 58pt disc): advertiser row
/// with the Skip chip, a non-seekable 6pt scrubber, the transport row (thumbs,
/// inert prev/next, play-pause), and the footer line + CTA pill.
///
/// Not ported: the two-back-presses escape hatch, the wide (16:9) picture variant (the native
/// `AdCreative` carries no `wideImageUrl`). Like / dislike persist through
/// `AdsRepository.react`; a reel has the like only.

struct AdBreakView: View {
    let pacing: AdPacingController

    @Environment(AppNavigationCoordinator.self) private var coordinator

    var body: some View {
        ZStack {
            PlayerStyle.black.ignoresSafeArea()
            if let ad = pacing.currentAd {
                if ad.assetType == "reel_video" {
                    ReelAdBreak(pacing: pacing, ad: ad, coordinator: coordinator)
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
                // Tablet/Mac: the transport stays a player-width column.
                .readableContentWidth(AdaptiveLayout.mediaColumnWidth)
        }
    }
}

/// Reel ad: the video on black, and only what a reel has over it. See the file
/// header for what is left out and why.
private struct ReelAdBreak: View {
    let pacing: AdPacingController
    let ad: AdCreative
    let coordinator: AppNavigationCoordinator

    private static let edge: CGFloat = 16

    var body: some View {
        ZStack {
            ReelVideo(pacing: pacing)
            VStack(spacing: 0) {
                topRow
                Spacer(minLength: 0)
                bottomColumn
            }
            .padding(.horizontal, Self.edge)
        }
    }

    private var topRow: some View {
        HStack(spacing: 8) {
            AdSponsoredBadge()
            Spacer(minLength: 0)
            AdBreakSkipChip(pacing: pacing)
            // Over footage we did not make, so the disc style: nothing else
            // guarantees the glyph can be seen. Respects the creative's own skip
            // lock, as in the audio layout: no second, hidden Skip.
            AdOptionsButton(ad: ad, onDismissAd: {
                guard pacing.canSkip else { return false }
                pacing.skip()
                return true
            }, style: .overlay, size: 22, overlaySize: 36)
        }
        .padding(.vertical, 8)
    }

    private var bottomColumn: some View {
        VStack(spacing: 12) {
            ReelLikeButton(ad: ad)
                .frame(maxWidth: .infinity, alignment: .trailing)
            if ad.hasDestination {
                AdBreakCta(pacing: pacing, ad: ad, coordinator: coordinator, horizontalPadding: 28, verticalPadding: 12)
            }
        }
        .padding(.bottom, 8 + 12)
    }
}

/// The reel's video at `reelVideoSize`, centred both ways: a reel that fills
/// the width is centred vertically, one scaled down to fit the height is
/// centred horizontally. A spinner until the player has reported the video's
/// shape — never a guessed one.
private struct ReelVideo: View {
    let pacing: AdPacingController

    var body: some View {
        GeometryReader { proxy in
            let size = reelVideoSize(available: proxy.size, aspectRatio: pacing.adVideoAspectRatio)
            ZStack {
                if let player = pacing.adPlayer, pacing.isAdReady, size != .zero {
                    ReelVideoSurface(player: player)
                        .frame(width: size.width, height: size.height)
                        // The reel counts once its picture has been seen, not once
                        // it plays: it plays on at the mini player too.
                        .reelSeen { pacing.reelWasSeen() }
                        .overlay {
                            // Opaque, so the whole video takes the tap.
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { pacing.togglePause() }
                                .accessibilityAddTraits(.isButton)
                                // `Text`, so the catalogue translates it: a ternary of
                                // bare literals is a `String`, which it never sees.
                                .accessibilityLabel(pacing.isAdPaused ? Text("Play") : Text("Pause"))
                        }
                        .overlay {
                            if pacing.isAdPaused { pausedMark }
                        }
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(PlayerStyle.whiteAlpha(0.54))
                        .scaleEffect(1.4)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }

    /// The play glyph over a paused reel, so a tap that paused it is seen to
    /// have done so and the next tap is known to resume it.
    private var pausedMark: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 44))
            .foregroundStyle(PlayerStyle.white)
            .padding(14)
            .background(Circle().fill(Color.black.opacity(0x8C / 255)))
            .allowsHitTesting(false)
            // The tap target under it already says "Play".
            .accessibilityHidden(true)
    }
}

/// Calls `onSeen` once the view has stayed up for half a second in a foreground
/// app: the dwell `AdImpressionTrigger` applies, plus the one thing that trigger
/// cannot know — whether the app is in front. A reel's video plays on whether or
/// not anyone is looking, so "it played" says nothing about "it was seen".
///
/// Restarted whenever the app comes or goes, so a dwell that began in front can
/// never finish behind. May call more than once (every return to the front);
/// `reelWasSeen` is idempotent.
private struct ReelSeen: ViewModifier {
    let onSeen: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.task(id: scenePhase) {
            guard scenePhase == .active else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            onSeen()
        }
    }
}

private extension View {
    func reelSeen(perform onSeen: @escaping () -> Void) -> some View {
        modifier(ReelSeen(onSeen: onSeen))
    }
}

/// A plain `AVPlayerLayer` at the size it is given. `.resizeAspect`, because the
/// frame already has the video's own shape (`reelVideoSize`): nothing to crop.
private struct ReelVideoSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}

private final class PlayerLayerView: UIView {
    let playerLayer = AVPlayerLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("PlayerLayerView is not built from a nib or storyboard")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

/// The reel's heart: the one reaction a reel has.
///
/// The same reaction as the audio layout's thumb-up — same wire value, same
/// toggle (`AdReaction.next`), same place it is remembered
/// (`AdsRepository.reaction(for:)`) — drawn as a heart because that is what a
/// like looks like on a reel. There is no dislike here: "Not interested" in the
/// ⋮ menu is how a listener makes an ad go away.
private struct ReelLikeButton: View {
    let ad: AdCreative

    @State private var reaction: AdReaction?
    private let ads: AdsRepository = DependencyContainer.current.resolve()

    var body: some View {
        let liked = reaction == .like
        Button {
            let next = AdReaction.next(current: reaction, tapped: .like)
            reaction = next
            ads.react(to: ad, next)
        } label: {
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(.system(size: 28))
                .foregroundStyle(liked ? PlayerStyle.white : PlayerStyle.whiteAlpha(0.7))
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.black.opacity(0x8C / 255)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Like this ad")
        .accessibilityAddTraits(liked ? .isSelected : [])
        // A different ad in the slot starts from what the repository holds for it.
        .task(id: ad.impressionToken) { reaction = ads.reaction(for: ad) }
    }
}

/// `_AdBreakSkipButton`: absent for an unskippable creative; while the wait
/// runs it shows the seconds left in a chip, then becomes live. Shared by both
/// layouts.
private struct AdBreakSkipChip: View {
    let pacing: AdPacingController

    var body: some View {
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
}

/// `_AdBreakCta`: the call-to-action pill. The label is the creative's own, or
/// "More Info"; it is dimmed and inert when there is nowhere to send the
/// listener. Shared by both layouts.
private struct AdBreakCta: View {
    let pacing: AdPacingController
    let ad: AdCreative
    let coordinator: AppNavigationCoordinator
    var horizontalPadding: CGFloat = 18
    var verticalPadding: CGFloat = 9

    private var label: String {
        ad.ctaLabel?.isEmpty == false ? (ad.ctaLabel ?? String(localized: "More Info")) : String(localized: "More Info")
    }

    var body: some View {
        let enabled = ad.hasDestination
        Button {
            if enabled { pacing.openAction(coordinator: coordinator) }
        } label: {
            Text(label)
                .typography(Typography.titleSmall)
                .foregroundStyle(enabled ? PlayerStyle.black : PlayerStyle.whiteAlpha(0.54))
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(Capsule().fill(enabled ? PlayerStyle.white : PlayerStyle.whiteAlpha(0.24)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
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
            AdBreakSkipChip(pacing: pacing)
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
            .accessibilityLabel(pacing.isAdPaused ? Text("Play") : Text("Pause"))
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
            AdBreakCta(pacing: pacing, ad: ad, coordinator: coordinator)
        }
    }
}
