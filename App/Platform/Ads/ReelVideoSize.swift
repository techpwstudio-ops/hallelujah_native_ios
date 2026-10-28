import CoreGraphics

/// Ports `lib/ads/reel_video_size.dart` — the size a reel ad's video is drawn
/// at inside `available`.
///
/// A reel is as wide as the screen and as tall as that makes it: width is the
/// available width and height is `width / aspectRatio`, so a 9:16 reel on a
/// 390-wide phone is 390 x 693 whatever the phone's height, and the caller
/// centres it vertically. Nothing is cropped and nothing is stretched.
///
/// When that height does not fit — a short screen, a landscape phone, a tablet
/// — the video is scaled DOWN to the largest box of its own shape that does,
/// and the caller centres it horizontally instead.
///
/// `.zero` when there is nothing sensible to draw: a video that has not
/// reported its shape yet (an aspect ratio of 0 or NaN), or an area with no
/// room in it. The caller shows its spinner for that, never a guessed shape.
///
/// Pure, so the arithmetic is tested without a screen.
func reelVideoSize(available: CGSize, aspectRatio: CGFloat) -> CGSize {
    guard aspectRatio.isFinite, aspectRatio > 0 else { return .zero }
    let width = available.width
    let height = available.height
    guard width.isFinite, height.isFinite, width > 0, height > 0 else { return .zero }

    let fullWidthHeight = width / aspectRatio
    if fullWidthHeight <= height { return CGSize(width: width, height: fullWidthHeight) }
    return CGSize(width: height * aspectRatio, height: height)
}
