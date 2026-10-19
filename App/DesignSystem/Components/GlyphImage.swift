import SwiftUI

/// A glyph named either as an SF Symbol or, with an `asset:` prefix, as one of
/// the Flutter brand SVGs imported into `Assets.xcassets/Icons`. Lets menu and
/// settings rows (which pass icons around as plain strings) show the same
/// artwork as the Flutter app without every call site branching.
struct GlyphImage: View {
    let name: String
    var size: CGFloat = 22

    private static let assetPrefix = "asset:"

    var body: some View {
        if name.hasPrefix(Self.assetPrefix) {
            Image(String(name.dropFirst(Self.assetPrefix.count)))
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: name)
                .font(.system(size: size))
        }
    }

    /// The Flutter artwork for the SF Symbols the song/content menus use
    /// (`song_menu_sheet.dart`: `ShareIcon`, `AddIcon`, `AddToQueueIcon`,
    /// `GoToArtistIcon`, `ClockIcon`, `CreditsIcon`, `ReportIcon`,
    /// `RemoveIcon`); any other symbol is returned unchanged.
    static func flutterName(forSymbol symbol: String) -> String {
        switch symbol {
        case "square.and.arrow.up": "asset:share"
        case "plus": "asset:add_circle"
        case "minus.circle": "asset:remove_circle"
        case "text.badge.plus": "asset:add_to_queue"
        case "person.crop.circle": "asset:go_to_artist"
        case "moon.zzz": "asset:clock"
        case "person.2": "asset:credits"
        case "flag": "asset:report"
        default: symbol
        }
    }
}
