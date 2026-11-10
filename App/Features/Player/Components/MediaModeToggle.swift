import SwiftUI

/// The pill at the artwork's bottom trailing corner that switches an episode between its cover and
/// its silent video: "Switch to video" while the cover is up, "Switch to audio" while the video is.
/// Draws nothing for a song that has no video.
struct MediaModeToggle: View {
    let isAvailable: Bool
    let isShowingVideo: Bool
    let action: () -> Void

    /// The glyph for what a tap goes to: the camera when it goes to the picture, headphones when it
    /// goes back to the audio.
    static func icon(isShowingVideo: Bool) -> IconToken {
        isShowingVideo ? .headphones : .video
    }

    static func title(isShowingVideo: Bool) -> String {
        isShowingVideo ? String(localized: "Switch to audio") : String(localized: "Switch to video")
    }

    var body: some View {
        if isAvailable {
            Button(action: action) {
                HStack(spacing: Dimens.spacing6) {
                    IconView(token: Self.icon(isShowingVideo: isShowingVideo), size: Dimens.iconSizeSmall)
                    Text(Self.title(isShowingVideo: isShowingVideo))
                        .typography(PlayerStyle.artworkControlLabel)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .foregroundStyle(PlayerStyle.white)
                .padding(.horizontal, Dimens.spacing12)
                .padding(.vertical, Dimens.spacing8)
                .background(PlayerStyle.artworkControlBackground, in: Capsule())
                // The pill is smaller than a finger; the button around it is not.
                .frame(minWidth: Spacing.minTapTarget, minHeight: Spacing.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Self.title(isShowingVideo: isShowingVideo))
            .accessibilityAddTraits(.isButton)
            // The frame is what sits in the corner, not the pill.
            .padding(.trailing, Dimens.spacing4)
            .padding(.bottom, Dimens.spacing2)
        }
    }
}

#Preview("Cover up: Switch to video") {
    MediaModeToggle(isAvailable: true, isShowingVideo: false, action: {})
        .padding()
        .background(Color.gray)
}

#Preview("Video up: Switch to audio") {
    MediaModeToggle(isAvailable: true, isShowingVideo: true, action: {})
        .padding()
        .background(Color.gray)
        .preferredColorScheme(.dark)
}
