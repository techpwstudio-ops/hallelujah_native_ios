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
    @State private var loadedURL: URL?
    /// Every attempt for `url` failed: a still placeholder, not a shimmer
    /// that would suggest it's still coming.
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(width: width, height: height)
                    .clipped()
            } else if didFail || url == nil {
                SkeletonBox(width: width, height: height, radius: 0)
            } else {
                // Flutter's dark shimmer while loading, not a flat grey box.
                SkeletonBox(width: width, height: height, radius: 0)
                    .shimmer()
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        // Keep what's showing until something replaces it: blanking first
        // made every reload (a page rebuilt by a skip or play tap) flash, and
        // a fetch that then failed left it black for good.
        // A different URL (the next song, the share card swapping to the
        // server's card image) keeps the old picture until the new one is
        // decoded, instead of flashing an empty box in between.
        didFail = false
        guard let url else {
            image = nil
            return
        }

        // One axis only, matching `_decodeSize`'s "preserve aspect ratio"
        // intent — `kCGImageSourceThumbnailMaxPixelSize` bounds the longer
        // dimension, so the *rendered* box's larger side is what's asked for.
        let maxPixelSize = max(width, height) * displayScale
        guard maxPixelSize.isFinite, maxPixelSize > 0 else { return }

        let requestedURL = url
        // Right after the phone wakes, the first requests often fail on a
        // dropped connection; one failure used to leave the artwork black
        // until the screen was rebuilt. Try again a couple of times.
        for delay in [0, 1, 3] {
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            let decoded = await ArtworkImageCache.shared.image(for: requestedURL, maxPixelSize: maxPixelSize)
            // `url` may have changed while the fetch was in flight (fast scroll
            // reusing this view's identity for a different row) — `.task(id:)`
            // already cancels the old task, but the awaited call can still
            // return after a new one starts; this guard drops the stale result
            // instead of flashing the wrong artwork for a frame.
            guard self.url == requestedURL else { return }
            if let decoded {
                image = decoded
                loadedURL = requestedURL
                return
            }
        }
        // Never leave another item's picture standing in for this one.
        if loadedURL != requestedURL { image = nil }
        didFail = true
    }
}
