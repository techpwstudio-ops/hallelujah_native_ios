import SwiftUI
import UIKit

/// The ad creatives' picture: `CachedNetworkImage` on a flexible frame. Decodes
/// through `ArtworkImageCache` at the same 1200pt cap `AdArtwork.warm` used, so
/// a creative the store already warmed paints from the cache with no
/// placeholder flash. Unlike `ArtworkView` it fills whatever frame it is given
/// (a banner's width is not known up front) and can `fit` as well as `fill`.
struct AdRemoteImage: View {
    let urlString: String
    var contentMode: ContentMode = .fill
    /// Painted while loading and on failure (`ColorTheme.darkFillColor`).
    var placeholder: Color = HomeColors.darkFill

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            placeholder
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            }
        }
        .clipped()
        .task(id: urlString) {
            image = nil
            guard let url = URL(string: urlString) else { return }
            let decoded = await ArtworkImageCache.shared.image(for: url, maxPixelSize: 1200)
            guard !Task.isCancelled else { return }
            image = decoded
        }
    }
}
