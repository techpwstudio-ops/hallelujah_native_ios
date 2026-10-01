import SwiftUI

/// The five tabs `DashBoardContainer`'s `IndexedStack` swaps between
/// (`lib/views/dashboard.dart`) — order matches `DashboardNavBloc`'s
/// `selectedIndex` exactly (Home=0, Search=1, AiPage=2, LibraryPage=3,
/// ReadPage=4). Labels are Dart's real bottom-nav-bar copy
/// (`lib/widgets/navigation/bottom_nav_bar.dart`) — `appLocalizations.*` for
/// four of them, and the literal `"Emet"` for AI (never localized in Dart,
/// so not localized here either). `ReadPage`'s label is "Bible", not
/// "Read" — the page/route class name and the tab label disagree in Dart
/// itself.
enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case home
    case search
    case aiAssistant
    case library
    case read

    var id: String { rawValue }

    var titleKey: LocalizedStringResource {
        switch self {
        case .home: "app.tab.home"
        case .search: "app.tab.search"
        case .aiAssistant: "app.tab.aiAssistant"
        case .library: "app.tab.library"
        case .read: "app.tab.read"
        }
    }

    var icon: IconToken {
        switch self {
        case .home: .tabHome
        case .search: .tabSearch
        case .aiAssistant: .tabAI
        case .library: .tabLibrary
        case .read: .tabRead
        }
    }

    /// `DashboardNavBloc._hiddenPlayerTabs = {2, 4}`
    /// (`lib/blocs/dashboard/dashboard_nav_bloc.dart`) — AI and Read/Bible
    /// always hide the mini player while selected, regardless of what's
    /// pushed on that tab's stack. Layered on top of (not instead of)
    /// `AppRoute.hidesMiniPlayer`; see `AppNavigationCoordinator.isMiniPlayerVisible`.
    var alwaysHidesMiniPlayer: Bool {
        switch self {
        case .aiAssistant, .read: true
        case .home, .search, .library: false
        }
    }
}
