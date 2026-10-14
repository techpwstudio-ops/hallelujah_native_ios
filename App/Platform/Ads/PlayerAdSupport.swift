import Foundation

/// Pure pieces of the player-side ad surfaces. Ports the small value types of
/// `lib/ads/player_ad_controller.dart` (`PlayerAdSurface`, `PlayerAdPacing`),
/// `AdTimeline` (`lib/ads/ad_creative.dart`) and `adBreakArtFor`
/// (`lib/ads/ad_break_art.dart`), kept free of UI and networking so they are
/// unit-testable.

/// Which of the audio player's two covers is on screen, and so which shape of ad
/// can stand in for it. Music's cover is a square, an episode's is 16:9, and an
/// ad laid over the cover has to be the same shape or it crops.
enum PlayerAdSurface: Sendable, Equatable {
    case music
    case episode

    /// The backend placement the ads for this cover are served from.
    var placement: String {
        switch self {
        case .music: "player_image_square"
        case .episode: "player_image_wide_16_9"
        }
    }

    /// The one format the placement is asked for, passed on every serve.
    var assetType: String {
        switch self {
        case .music: "image_square"
        case .episode: "image_wide_16_9"
        }
    }

    /// `PlayerAdSurface.forSongType` — `Song.type == "music"` is a song, anything
    /// else an episode.
    static func forSongType(_ type: String?) -> PlayerAdSurface {
        type == "music" ? .music : .episode
    }

    /// Native cover shape (`Song.displayAspectRatio`): 16:9 only for an episode.
    /// The ad must fit the cover it covers, so the native player decides on this.
    static func forCover(isEpisode: Bool) -> PlayerAdSurface {
        isEpisode ? .episode : .music
    }
}

/// Where the takeover is in a song's cycle.
enum PlayerAdPhase: Sendable, Equatable {
    /// The song's own cover is up — when a song starts, and between two ads.
    case organic
    /// An ad is covering the cover.
    case showing
}

/// `AdTimeline`: the song's own artwork for `introSeconds`, then an ad for
/// `displaySeconds`, then the artwork again for `gapSeconds`, and so on until the
/// song changes. The numbers are the dashboard's; the defaults are what the
/// backend seeds.
struct AdTimeline: Sendable, Equatable {
    static let defaultIntroSeconds = 3
    static let defaultDisplaySeconds = 30
    static let defaultGapSeconds = 5

    static let introRange = 0...120
    static let displayRange = 5...600
    static let gapRange = 1...120

    var introSeconds: Int = AdTimeline.defaultIntroSeconds
    var displaySeconds: Int = AdTimeline.defaultDisplaySeconds
    var gapSeconds: Int = AdTimeline.defaultGapSeconds

    /// Fills blanks with the defaults and holds every field to the range the
    /// dashboard accepts (`AdTimeline.resolve`).
    static func resolve(introSeconds: Int?, displaySeconds: Int?, gapSeconds: Int?) -> AdTimeline {
        AdTimeline(
            introSeconds: clamp(introSeconds ?? defaultIntroSeconds, introRange),
            displaySeconds: clamp(displaySeconds ?? defaultDisplaySeconds, displayRange),
            gapSeconds: clamp(gapSeconds ?? defaultGapSeconds, gapRange)
        )
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

/// Decides which songs get the takeover: one in every N, N being the placement's
/// Pacing field — 1, the default, being every song (`PlayerAdPacing`).
@MainActor
final class PlayerAdPacing {
    private var songID: String?
    private var takes = false
    private var songsSinceDisplay = 0

    init() {}

    /// Whether `songID` gets the takeover. Asked again about the same song it
    /// answers what it answered the first time and does not count it twice.
    func takesOver(_ songID: String, everyN: Int) -> Bool {
        if songID == self.songID { return takes }
        self.songID = songID
        songsSinceDisplay += 1
        takes = songsSinceDisplay >= everyN
        return takes
    }

    /// An ad was actually put in front of the listener, which restarts the
    /// count. Deliberately not at the decision: a song that was due but had no
    /// ad to show stays due.
    func markDisplayed() {
        songsSinceDisplay = 0
    }
}

/// The picture an audio ad break shows, and the shape it is meant to be seen in
/// (`AdBreakArt`).
struct AdBreakArt: Sendable, Equatable {
    let url: String
    /// Width over height: 1 for the square, 16 / 9 for the wide picture.
    let aspectRatio: Double
}

/// `adBreakArtFor`: the picture shaped like the cover goes where the cover goes;
/// a campaign without it gets the one it has, whole. Nil only when the creative
/// has no picture at all.
func adBreakArt(for ad: AdCreative, isMusic: Bool) -> AdBreakArt? {
    let square = ad.companionImageUrl ?? ad.squareImageUrl
    let wide = ad.wideImageUrl
    let squareArt = square.map { AdBreakArt(url: $0, aspectRatio: 1) }
    let wideArt = wide.map { AdBreakArt(url: $0, aspectRatio: 16.0 / 9.0) }
    return isMusic ? (squareArt ?? wideArt) : (wideArt ?? squareArt)
}

/// What an ad surface titles itself with (`player_ad_strip.dart` /
/// `player_ad_card.dart`): the headline is what the ad says, the advertiser is
/// who says it; with no headline the advertiser's name is the line.
struct AdCaption: Equatable {
    let title: String
    let subtitle: String

    init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }

    init(ad: AdCreative) {
        let headline = ad.headline?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let advertiser = ad.advertiserName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        title = headline.isEmpty ? advertiser : headline
        subtitle = headline.isEmpty ? "" : advertiser
    }
}

extension AdCreative {
    /// An ad with nowhere to send the listener has no business offering a button.
    var hasDestination: Bool { action != nil || clickUrl != nil }

    /// The call-to-action label of the player's strip and card.
    var playerCTALabel: String {
        let label = ctaLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return label.isEmpty ? "Learn more" : label
    }
}
