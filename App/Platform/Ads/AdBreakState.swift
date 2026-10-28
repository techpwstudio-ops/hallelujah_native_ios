import CoreGraphics
import Foundation

extension AdCreative {
    /// A `reel_video`: the one break format that draws a picture, and so the one
    /// whose impression waits for the picture to be seen.
    var isReel: Bool { assetType == "reel_video" }
}

/// What has happened so far in one ad break, and what that means for the
/// server's counters: when the impression counts, what a break that will not
/// play has to say, and whether anything stays up after it.
///
/// Pure on purpose, like `AdBreakFill`: `AdPacingController` owns the player and
/// the timing and feeds this what the player reports, so the rules — which
/// decide what is billed — are tested without a player.
struct AdBreakProgress: Equatable, Sendable {
    /// The item has loaded far enough to play.
    private(set) var itemIsReady = false

    /// Width over height of the playing video, 0 until the item has reported its
    /// shape.
    private(set) var videoAspectRatio: CGFloat = 0

    /// A reel's picture has been on screen, in a foreground app, long enough to
    /// count.
    private(set) var pictureSeen = false

    /// The impression for this break has been sent.
    private(set) var impressionCounted = false

    mutating func itemBecameReady() {
        itemIsReady = true
    }

    /// An item that has not worked out its shape reports a zero size, which is
    /// not a shape: the ratio stays 0 until there is a real one.
    mutating func itemReportedSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        videoAspectRatio = size.width / size.height
    }

    mutating func pictureWasSeen() {
        pictureSeen = true
    }

    mutating func impressionWasSent() {
        impressionCounted = true
    }

    /// The break is under way: the item can play and, for a reel, has said what
    /// shape it is drawn at. All the break needs, whether or not anyone is
    /// looking.
    func isUnderway(_ ad: AdCreative) -> Bool {
        itemIsReady && (!ad.isReel || videoAspectRatio > 0)
    }

    /// Whether the impression is sent now: once per break, and only for a
    /// creative genuinely there to be had. An audio ad is heard the moment it
    /// plays; a reel also has to have been seen, because it plays whether or not
    /// anyone is looking at it (the full player can be down at the mini player).
    func shouldCountImpression(_ ad: AdCreative) -> Bool {
        guard !impressionCounted, isUnderway(ad) else { return false }
        return !ad.isReel || pictureSeen
    }

    /// What a break that will not play tells the server, or nil when its
    /// impression has already counted: the creative was shown, so "not shown"
    /// would be the other story for the same token.
    func notShownReason(afterFailureOf ad: AdCreative) -> AdNotShownReason? {
        guard !impressionCounted else { return nil }
        return ad.isReel ? .videoInitFailed : .preloadFailed
    }

    /// Whether the ad stays up as a companion banner when its break ends. Only an
    /// ad that was shown has anything to leave behind on screen.
    func leavesCompanion(_ ad: AdCreative) -> Bool {
        impressionCounted && ad.lingerAfterDismiss && ad.companionImageUrl != nil
    }
}

/// Whether the ad's player reads as paused, and whose pause it is.
///
/// An `AVPlayer` does not start again by itself after an interruption, so a
/// pause the system made has to be shown (a tap can then resume it) and taken
/// back when iOS says playback may go on. A pause the listener made is theirs
/// to undo, and nothing the player later reports may undo it.
struct AdPauseState: Equatable, Sendable {
    private(set) var isPaused = false

    /// The pause was the system's — an interruption, the route going away — not
    /// the listener's.
    private(set) var isBySystem = false

    /// The ad's player stopped without a tap of the listener's. A finished item
    /// pauses its player on the way to the end of the break; that is the end of
    /// the ad, not a pause to show. Already paused is left as it is, whoever's
    /// pause that was.
    mutating func playerStopped(itemFinished: Bool) {
        guard !isPaused, !itemFinished else { return }
        isPaused = true
        isBySystem = true
    }

    /// The ad's player is playing, or waiting to. Only a pause the system made is
    /// the system's to take back.
    mutating func playerStarted() {
        guard isPaused, isBySystem else { return }
        isPaused = false
        isBySystem = false
    }

    /// The listener's tap on the ad: the pause is theirs from now on, taking a
    /// system one over when it was showing. Returns whether the ad is now paused.
    mutating func listenerToggled() -> Bool {
        isPaused.toggle()
        isBySystem = false
        return isPaused
    }

    /// iOS ended an interruption. Returns whether the ad's player should be
    /// started again — only when the interruption is what stopped it, and iOS
    /// says playback may resume.
    mutating func interruptionEnded(shouldResume: Bool) -> Bool {
        guard isPaused, isBySystem, shouldResume else { return false }
        isPaused = false
        isBySystem = false
        return true
    }
}
