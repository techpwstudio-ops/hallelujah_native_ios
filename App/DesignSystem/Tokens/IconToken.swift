import SwiftUI

/// SF Symbols for the app's icon vocabulary. Grows per-feature as screens are
/// built, the same posture as `LogCategory` (T04) — not pre-declared in full.
///
/// The tab bar cases are grounded in the actual Flutter source
/// (`lib/widgets/navigation/bottom_nav_bar.dart`: Home, Search, AI, Library,
/// Read), but that source renders them from custom brand SVGs
/// (`assets/icons/homeoutline.svg`, `searchoutline.svg`, `ai_icon.svg`,
/// `libraryoutline.svg`, `bookoutline.svg`), not a system icon font. The SF
/// Symbol names below are the closest system equivalents, used as a
/// placeholder — getting the real brand glyphs onto screen needs those SVGs
/// converted to vector PDF/template images in `Assets.xcassets`, which needs
/// actual asset-conversion tooling, not just this file. Deferred to T17
/// (Glass tab bar and mini-player dock), noted there so it isn't lost.
enum IconToken: CaseIterable, Sendable {
    case tabHome
    case tabSearch
    case tabAI
    case tabLibrary
    case tabRead

    case back
    case close
    case share
    case download
    case favorite
    case favoriteFilled
    case more

    case play
    case pause
    case next
    case previous
    case shuffle
    case repeatOne
    case repeatAll

    // Added for T12 (Core components): `AppTextField`'s obscure-text toggle
    // (grounded in `app_text_field.dart`'s `Icons.visibility`/
    // `Icons.visibility_off`) and `ErrorStateView`'s glyph/retry action, which
    // has no Flutter precedent to ground against (`Empty`, the closest Dart
    // widget, is a bare `TODO`-marked text label — see `StateViews.swift`).
    case visibilityOn
    case visibilityOff
    case warning
    case retry

    // Added for T19 (`NoNetworkBanner`, ported from
    // `no_network_banner.dart`'s `wifi_off_rounded`/`arrow_forward_ios_rounded`
    // — its third icon, `close_rounded`, is already `.close` above).
    case noNetwork
    case chevronForward

    // Added for T21 (phone auth + country picker). `google`/`apple` stand in
    // for `assets/icons/google.svg`/`apple.svg`
    // (`social_sign_in_buttons.dart`) — brand marks, not system glyphs, same
    // placeholder-pending-real-asset situation as the tab bar icons above.
    // `phone`/`mail` stand in for that same widget's `phone.svg`/`email.svg`
    // toggle icons. `edit` is `EditIcon` (`widgets/icons.dart`'s
    // `edit.svg`), `chevronDown` is the country-code picker's
    // `Icons.arrow_drop_down_outlined`, `search` is the country picker
    // sheet's `Icons.search`.
    case chevronDown
    case search
    case edit
    case phone
    case mail
    case google
    case apple

    /// Added for T24 (account setup). `Icons.calendar_today_outlined`
    /// (`custom_inputs.dart`'s `dateInput`).
    case calendar

    /// Added for T35 (Full player screen): the queue entry point
    /// (`_QueueAndShareRow`'s `Icons.menu`, `audio_player_screen.dart`) —
    /// `list.bullet` used instead of a literal hamburger glyph, since a
    /// menu icon reads as navigation chrome in iOS, not "show the queue,"
    /// the same "closest system equivalent, not a literal port" placeholder
    /// status this enum's own header comment already established for every
    /// brand-SVG icon.
    case queue

    /// Added for T40 (Search): `RecentSearches`'s per-row leading glyph
    /// (`content_search_page.dart`) — Dart draws its own inline history-clock
    /// SVG there rather than a Material icon, so this is a closest-system-
    /// equivalent placeholder, the same posture as every other brand-SVG
    /// case in this enum's header comment.
    case recentSearch

    /// Added for T43 (Library home): the "Liked Artists" quick-link tile
    /// (`liked_artists.svg`, `library_item_ui.dart`) — no existing case
    /// covers a person/artist glyph, so this is a new closest-system-
    /// equivalent placeholder, same posture as every other brand-SVG case
    /// in this enum's header comment.
    case artists

    /// Added for T45 (User playlist detail): the swipe-to-remove-song row
    /// action. No Dart SVG precedent — `user_playlist_songs.dart`'s admin
    /// controls (`Icons.add_circle_outline`/`Icons.more_vert`) have no
    /// delete/trash glyph of their own to port — so this is a closest-
    /// system-equivalent placeholder, same posture as every other brand-SVG
    /// case in this enum's header comment.
    case trash

    /// Added for T56 (Verse of the day): `VerseOfDayActionBar`'s comment
    /// and history slots (`verse_action_bar.dart`) — no existing case
    /// covers a comment-bubble or restore-history glyph (`.recentSearch`
    /// is specifically "recent search," not general history), so these are
    /// closest-system-equivalent placeholders, same posture as every other
    /// brand-SVG case in this enum's header comment.
    case comment
    case history

    var systemName: String {
        switch self {
        case .tabHome: "house"
        case .tabSearch: "magnifyingglass"
        case .tabAI: "sparkles"
        case .tabLibrary: "square.stack"
        case .tabRead: "book"
        case .back: "chevron.left"
        case .close: "xmark"
        case .share: "square.and.arrow.up"
        case .download: "arrow.down.circle"
        case .favorite: "heart"
        case .favoriteFilled: "heart.fill"
        case .more: "ellipsis"
        case .play: "play.fill"
        case .pause: "pause.fill"
        case .next: "forward.fill"
        case .previous: "backward.fill"
        case .shuffle: "shuffle"
        case .repeatOne: "repeat.1"
        case .repeatAll: "repeat"
        case .visibilityOn: "eye"
        case .visibilityOff: "eye.slash"
        case .warning: "exclamationmark.triangle"
        case .retry: "arrow.clockwise"
        case .noNetwork: "wifi.slash"
        case .chevronForward: "chevron.right"
        case .chevronDown: "chevron.down"
        case .search: "magnifyingglass"
        case .edit: "pencil"
        case .phone: "phone.fill"
        case .mail: "envelope.fill"
        case .google: "g.circle.fill"
        case .apple: "apple.logo"
        case .calendar: "calendar"
        case .queue: "list.bullet"
        case .recentSearch: "clock"
        case .artists: "person.2.fill"
        case .trash: "trash"
        case .comment: "bubble.left"
        case .history: "clock.arrow.circlepath"
        }
    }

    /// The Flutter brand SVG (`assets/icons/*.svg`, imported into
    /// `Assets.xcassets/Icons`) this token mirrors, or nil where Flutter itself
    /// draws a Material icon and the SF Symbol is the right counterpart.
    var assetName: String? {
        switch self {
        case .tabHome: "homeoutline"
        case .tabSearch: "searchoutline"
        case .tabAI: "ai_icon"
        case .tabLibrary: "libraryoutline"
        case .tabRead: "bookoutline"
        case .back: "arrow_left"
        case .share: "share"
        case .favorite: "like"
        case .favoriteFilled: "liked"
        case .shuffle: "shuffle"
        case .repeatOne, .repeatAll: "loop"
        case .queue: "menu"
        case .recentSearch: "clock"
        case .trash: "trash"
        case .comment: "comments"
        case .history: "recent"
        case .edit: "edit"
        default: nil
        }
    }

    var image: Image { Image(systemName: systemName) }
}

/// An `IconToken` drawn at an explicit point size: the brand SVG when the token
/// has one (assets ignore `.font`, so they are framed instead), otherwise the SF
/// Symbol at the same size. Tinted by `foregroundStyle` like any template image (the coloured `liked` heart keeps its own red).
struct IconView: View {
    let token: IconToken
    var size: CGFloat = 24

    var body: some View {
        if let assetName = token.assetName {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: token.systemName)
                .font(.system(size: size))
        }
    }
}
