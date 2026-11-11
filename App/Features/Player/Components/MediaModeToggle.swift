import SwiftUI

/// The icon button in the player's queue / share row that switches an episode between its cover
/// and its silent video. It sits just left of Share, in the same 44 pt box with the same 20 pt
/// glyph, so the two read as a pair. The glyph is where a tap goes: a camera while the cover is
/// up, headphones while the video is. VoiceOver reads "Switch to video" / "Switch to audio".
/// The player shows it only for an episode that has a video.
///
/// Video is a premium feature (`PremiumFeature.videoMode`). While it is locked the camera carries a
/// small lock badge, and the tap is the caller's to route to the subscription plans, as a locked
/// download or sleep timer is.
struct MediaModeToggle: View {
    let isShowingVideo: Bool
    var isLocked = false
    let action: () -> Void

    @Environment(\.appTheme) private var theme

    /// Size of the lock badge on a locked switch.
    static let lockBadgeSize: CGFloat = 10

    /// The glyph for what a tap goes to: the camera when it goes to the picture, headphones when it
    /// goes back to the audio. Outline glyphs, to match Share beside it.
    static func systemName(isShowingVideo: Bool) -> String {
        isShowingVideo ? "headphones" : "video"
    }

    static func title(isShowingVideo: Bool) -> String {
        isShowingVideo ? String(localized: "Switch to audio") : String(localized: "Switch to video")
    }

    var body: some View {
        Button {
            HapticFeedback.selection.trigger()
            action()
        } label: {
            Image(systemName: Self.systemName(isShowingVideo: isShowingVideo && !isLocked))
                .font(.system(size: PlayerStyle.queueRowGlyphSize, weight: .medium))
                .foregroundStyle(PlayerStyle.white)
                .overlay(alignment: .bottomTrailing) {
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: Self.lockBadgeSize, weight: .bold))
                            .foregroundStyle(theme.color(.brandPrimary))
                            .offset(x: Self.lockBadgeSize / 2, y: Self.lockBadgeSize / 4)
                    }
                }
                // Glyph on the box's trailing edge, like Share's, so the gap between the two
                // glyphs is the same whichever symbol is showing.
                .frame(width: PlayerStyle.queueRowBox, height: PlayerStyle.queueRowBox, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.title(isShowingVideo: isShowingVideo && !isLocked))
        .accessibilityHint(isLocked ? String(localized: "Premium") : "")
    }
}

#Preview("Cover up: camera") {
    MediaModeToggle(isShowingVideo: false, action: {})
        .padding()
        .background(PlayerStyle.black)
        .preferredColorScheme(.dark)
}

#Preview("Locked: camera with a lock") {
    MediaModeToggle(isShowingVideo: false, isLocked: true, action: {})
        .padding()
        .background(PlayerStyle.black)
        .preferredColorScheme(.dark)
}

#Preview("Video up: headphones") {
    MediaModeToggle(isShowingVideo: true, action: {})
        .padding()
        .background(PlayerStyle.black)
        .preferredColorScheme(.dark)
}
