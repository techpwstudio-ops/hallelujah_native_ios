import AVFoundation
import SwiftUI
import UIKit

/// An `AVPlayerLayer` at the size it is given, drawing `player` with the given gravity.
///
/// Shared by the reel ad (`.resizeAspect`: its frame already has the video's own shape, so there
/// is nothing to crop) and the episode's silent video (`.resizeAspectFill` when the picture is the
/// cover's shape, so it fills it, and `.resizeAspect` otherwise). The view clips to its bounds, so a
/// filled picture is cropped to the box instead of spilling out of it.
struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect
    /// Shown wherever the picture does not reach: the bars of a fitted video.
    var background: Color = PlayerStyle.black

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = gravity
        view.backgroundColor = UIColor(background)
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
        if view.playerLayer.videoGravity != gravity {
            // A gravity change animates by default; the picture should simply be right.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view.playerLayer.videoGravity = gravity
            CATransaction.commit()
        }
        let color = UIColor(background)
        if view.backgroundColor != color { view.backgroundColor = color }
    }
}

final class PlayerLayerView: UIView {
    let playerLayer = AVPlayerLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("PlayerLayerView is not built from a nib or storyboard")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}
