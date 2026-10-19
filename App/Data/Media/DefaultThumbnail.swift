import Foundation

/// `S3Service.defaultThumbnailUrl` (`lib/services/s3_service.dart`): the shared
/// public letter tile that stands in for an image-less user, creator or
/// playlist (`LoadImage(fallbackName:)`, `lib/widgets/image_loader.dart`).
///
/// Mirrors `AvatarGenerator.keyFor` on the backend: the first ALPHABETIC
/// character anywhere in the name, else the first digit, else `default`.
/// Titles open with emoji, quotes and "1. " numbering often enough that "the
/// first character" would point at keys that don't exist (there is no
/// `🎵.webp`), which is a 404 and a blank tile. Deriving it client-side means
/// the tile shown before the server says anything is the very object the
/// server will name later.
enum DefaultThumbnail {
    /// `hallelujah/system/public/avatars/<symbol>.webp`, or `nil` for a nil
    /// name (Dart returns null and the caller shows its flat placeholder).
    static func path(for name: String?) -> String? {
        guard let name else { return nil }
        let normalized = foldDiacritics(name.lowercased())
        let symbol = firstScalar(in: normalized, matching: { ("a"..."z").contains($0) })
            ?? firstScalar(in: normalized, matching: { ("0"..."9").contains($0) })
            ?? "default"
        return "hallelujah/system/public/avatars/\(symbol).webp"
    }

    /// Whether `path` is no real cover yet: nothing stored, or the shared
    /// letter tile (`hallelujah/system/public/avatars/…`) the backend seeds
    /// until a playlist's own collage has been composited
    /// (`user-playlists.job.js`).
    static func isLetterTile(path: String?) -> Bool {
        guard let path, !path.isEmpty else { return true }
        return path.contains("hallelujah/system/public/avatars")
    }

    /// Latin-1 accented letters -> their base letter, so "Ávila" lands on `a`
    /// like it does on the server (which folds via NFD). Anything outside
    /// this range falls through to the digit/default branches, same as there.
    static func foldDiacritics(_ input: String) -> String {
        let accented = Array("àáâãäåçèéêëìíîïñòóôõöùúûüýÿ")
        let plain = Array("aaaaaaceeeeiiiinooooouuuuyy")
        var result = ""
        for character in input {
            if let index = accented.firstIndex(of: character) {
                result.append(plain[index])
            } else {
                result.append(character)
            }
        }
        return result
    }

    private static func firstScalar(in text: String, matching predicate: (Character) -> Bool) -> String? {
        text.first(where: predicate).map(String.init)
    }
}

extension ArtworkURLResolver {
    /// The letter-tile URL for `name`, resolved through the same proxy
    /// fallback every non-thumbnail path takes in `getFileUrl`.
    func resolveDefaultThumbnail(name: String?) -> URL? {
        resolve(path: DefaultThumbnail.path(for: name), variant: .md, allowedVariants: nil)
    }

    /// `LoadImage(path:, fallbackName:)` (`effectivePath`/`effectiveVariants`):
    /// a stored cover always wins; only when there is no path does the letter
    /// tile for `fallbackName` stand in. A brand-new playlist has no path
    /// until the server has composited its cover, and the flat skeleton reads
    /// as a broken image rather than as a playlist. The tile carries no
    /// variants — it has no `sm.webp` sibling — so `allowedVariants` only
    /// applies to the stored path. A nil/empty name yields `nil`, same as
    /// Dart returning the (null) path.
    func resolve(path: String?, variant: ImageVariant, allowedVariants: String?, fallbackName: String?) -> URL? {
        if let path, !path.isEmpty {
            return resolve(path: path, variant: variant, allowedVariants: allowedVariants)
        }
        guard let fallbackName, !fallbackName.isEmpty else { return nil }
        return resolveDefaultThumbnail(name: fallbackName)
    }
}
