import UIKit

/// `warmAdArtwork` (`lib/ads/ad_artwork.dart`): downloads and decodes an ad's
/// picture ahead of the slot that will show it, so the slot only ever opens
/// with a picture in it. `false` when it can't be loaded within 8s — which
/// makes the ad no ad at all.
enum AdArtwork {
    static let timeout: Duration = .seconds(8)

    static func warm(_ ad: AdCreative) async -> Bool {
        guard let raw = ad.assetUrl, let url = URL(string: raw) else { return false }
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await ArtworkImageCache.shared.image(for: url, maxPixelSize: 1200) != nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }
}
