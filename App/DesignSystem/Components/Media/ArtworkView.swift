import SwiftUI
import UIKit

/// Displays artwork at an already-resolved `URL?` — CDN variant selection
/// lives in `App/Data/Media/ArtworkURLResolver`, kept out of this file so
/// DesignSystem stays free of any `AppConfiguration` dependency (D2).
///
/// Ports `LoadImage`'s decode behavior (`lib/widgets/image_loader.dart`),
/// not its full widget surface: no `assetPath`/`fallbackName` branch (this
/// app has no bundled-asset artwork case yet, and letter-tile fallback is
/// itself a *server-generated* URL in Dart — `S3Service.defaultThumbnailUrl`
/// — not client-drawn, so it needs no separate rendering path here, only a
/// resolved `URL?` like any other artwork). The behavior that matters is
/// preserved exactly: a plain, non-shimmering fill both while loading *and*
/// on a nil/failed URL (Dart's own default placeholder is a flat
/// `Container(color: Colors.white.withOpacity(0.1))`, used both for "no
/// path" and inside `errorBuilder` — not an animated shimmer; a whole
/// *screen's* worth of these gets wrapped in one `.shimmer()` at the call
/// site, per `ShimmerModifier`'s own "ONE Shimmer PER SECTION" rule, not
/// each artwork view wrapping itself).
///
/// Downsampling (`ArtworkImageCache`, `ImageIO`) is this file's actual
/// native contribution: `Image(url:)`/`AsyncImage` would decode at the
/// source's full resolution regardless of how small this view renders,
/// which is exactly the memory problem Dart's `ResizeImage` wrapping exists
/// to avoid.
struct ArtworkView: View {
    let url: URL?
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat = Radius.md
    var contentMode: ContentMode = .fill

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                SkeletonBox(width: width, height: height, radius: 0)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        image = nil
        guard let url else { return }

        // One axis only, matching `_decodeSize`'s "preserve aspect ratio"
        // intent — `kCGImageSourceThumbnailMaxPixelSize` bounds the longer
        // dimension, so the *rendered* box's larger side is what's asked for.
        let maxPixelSize = max(width, height) * displayScale
        guard maxPixelSize.isFinite, maxPixelSize > 0 else { return }

        let requestedURL = url
        let decoded = await ArtworkImageCache.shared.image(for: requestedURL, maxPixelSize: maxPixelSize)
        // `url` may have changed while the fetch was in flight (fast scroll
        // reusing this view's identity for a different row) — `.task(id:)`
        // already cancels the old task, but the awaited call can still
        // return after a new one starts; this guard drops the stale result
        // instead of flashing the wrong artwork for a frame.
        guard self.url == requestedURL else { return }
        image = decoded
    }
}
