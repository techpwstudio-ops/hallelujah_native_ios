import SwiftUI
import UIKit

/// System share sheet for a minted user-playlist link. `ShareSheetView`'s
/// `ShareTarget` has no user-playlist case yet, so the link
/// (`DeepLinkService.userPlaylistShareLink`) goes through the stock sheet.
struct PlaylistShareItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}

struct PlaylistActivitySheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
