import Photos
import UIKit

/// Saves images to Photos. The `performChanges` block is built here, in a
/// nonisolated context, on purpose: Photos runs it on its own background
/// queue, and under Swift 6 a closure written inside a `@MainActor` method
/// (every SwiftUI view's) is main-actor isolated, so the runtime isolation
/// check traps the moment Photos calls it — the "Save Image" crash. Same
/// reason `NowPlayingCoordinator.makeArtwork` is nonisolated.
enum PhotoLibrarySaver {
    nonisolated static func save(_ image: UIImage) async throws {
        try await PHPhotoLibrary.shared().performChanges(changes(for: image))
    }

    nonisolated static func save(imageData data: Data) async throws {
        try await PHPhotoLibrary.shared().performChanges(changes(for: data))
    }

    private nonisolated static func changes(for image: UIImage) -> @Sendable () -> Void {
        { _ = PHAssetChangeRequest.creationRequestForAsset(from: image) }
    }

    private nonisolated static func changes(for data: Data) -> @Sendable () -> Void {
        {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }
    }
}
