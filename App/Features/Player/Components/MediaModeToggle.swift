import SwiftUI

/// The chip under the artwork that switches an episode between its cover and its silent video:
/// "Switch to video" while the cover is up, "Switch to audio" while the video is. It is a
/// `PlayerChip`, so it looks like the Chapters chip beside it. The chip row decides whether it is
/// there at all: only for an episode that has a video.
struct MediaModeToggle: View {
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
        PlayerChip(
            systemName: Self.icon(isShowingVideo: isShowingVideo).systemName,
            title: Self.title(isShowingVideo: isShowingVideo),
            action: action
        )
    }
}

#Preview("Cover up: Switch to video") {
    MediaModeToggle(isShowingVideo: false, action: {})
        .padding()
        .background(PlayerStyle.black)
        .preferredColorScheme(.dark)
}

#Preview("Video up: Switch to audio") {
    MediaModeToggle(isShowingVideo: true, action: {})
        .padding()
        .background(PlayerStyle.black)
        .preferredColorScheme(.dark)
}
