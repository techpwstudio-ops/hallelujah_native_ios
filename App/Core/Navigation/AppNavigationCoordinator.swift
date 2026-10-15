import Foundation
import SwiftUI

/// The native replacement for Dart's single shared `GoRouter`/
/// `appNavigatorKey` Navigator plus `NavigationService`
/// (`lib/services/navigation_service.dart`). Dart's dashboard
/// (`lib/views/dashboard.dart`) has no per-tab navigation stacks at all —
/// its `IndexedStack` only swaps which tab's *root* is visible, and every
/// push from any tab lands on that one shared Navigator. Giving each tab
/// its own path here is a deliberate native-only upgrade (the roadmap's own
/// ask), not a port of that behavior.
///
/// Owned by `AppShellView` as `@State` and handed down via `.environment`,
/// not registered in `DependencyContainer`: it's view-tree-scoped UI state
/// (its lifetime is the app shell's), not a backend service like the DI
/// container's other registrations.
@Observable
@MainActor
final class AppNavigationCoordinator {
    var selectedTab: AppTab
    private(set) var tabPaths: [AppTab: [AppRoute]]
    var presentedFullScreen: FullScreenDestination?
    private(set) var playerPath: [PlayerRoute] = []

    /// Ground-truth flag mirroring `DashboardNavBloc._canShowPlayer`
    /// (`lib/blocs/dashboard/dashboard_nav_bloc.dart`) — is there an active,
    /// started song right now? Nothing sets this `true` yet: no playback
    /// state exists until T34 (Mini player), which owns flipping it from
    /// there. Until then `isMiniPlayerVisible` is always `false`, the same
    /// "nothing playing, nothing shown" state Dart starts in too.
    var isPlaybackActive = false

    /// Mirrors `ios26OpenSheetCount` (`lib/widgets/navigation/
    /// our_adaptive_scaffold.dart`) — hides the dock while any `.appSheet()`
    /// (T12) is open, on every platform, not just the ones where the visual
    /// overlap Dart's comment describes actually happens. Managed by
    /// `AppSheetContainer`'s `onAppear`/`onDisappear` (`AppSheet.swift`).
    private(set) var openSheetCount = 0

    init(selectedTab: AppTab = .home) {
        self.selectedTab = selectedTab
        tabPaths = Dictionary(uniqueKeysWithValues: AppTab.allCases.map { ($0, []) })
    }

    /// `Binding` so `NavigationStack(path:)` can both read a tab's path and
    /// write back the trims SwiftUI makes on its own (swipe-back, the
    /// system back button) — the same two-way relationship Dart's
    /// `NavigationService.onRouteChanged` exists to keep in sync by hand.
    func path(for tab: AppTab) -> Binding<[AppRoute]> {
        Binding(
            get: { self.tabPaths[tab, default: []] },
            set: { self.tabPaths[tab] = $0 }
        )
    }

    func push(_ route: AppRoute, in tab: AppTab? = nil) {
        tabPaths[tab ?? selectedTab, default: []].append(route)
    }

    func pop(in tab: AppTab? = nil) {
        let tab = tab ?? selectedTab
        guard tabPaths[tab]?.isEmpty == false else { return }
        tabPaths[tab]?.removeLast()
    }

    func popToRoot(in tab: AppTab? = nil) {
        tabPaths[tab ?? selectedTab] = []
    }

    /// Clears every tab's stack and dismisses whatever full-screen
    /// presentation is up — the shell-level equivalent of Dart's
    /// `NavigationService.offAll`. `RootView`'s `.authentication`/`.app`
    /// switch already handles the sign-in/out reset itself (T20-24); this
    /// is for resetting *within* the shell once already in `.app` — e.g. a
    /// deep link (T18) landing on a specific tab.
    func resetToRoot(selecting tab: AppTab = .home) {
        selectedTab = tab
        tabPaths = Dictionary(uniqueKeysWithValues: AppTab.allCases.map { ($0, []) })
        dismissFullScreen()
    }

    func presentPlayer() {
        presentedFullScreen = .player
    }

    func presentAIVoiceOverlay() {
        presentedFullScreen = .aiVoiceOverlay
    }

    func presentAIAudioConversation(conversationID: String?) {
        presentedFullScreen = .aiAudioConversation(conversationID: conversationID)
    }

    func setPlayerPath(_ path: [PlayerRoute]) {
        playerPath = path
    }

    func pushInPlayer(_ route: PlayerRoute) {
        playerPath.append(route)
    }

    func dismissFullScreen() {
        presentedFullScreen = nil
        playerPath = []
    }

    /// `NavigationService.popPlayerScreens()`
    /// (`lib/services/navigation_service.dart`): "leave every screen that
    /// belongs to the current playback session." Dart pops its one shared
    /// Navigator until it finds a route outside `playerOwnedRoutes`, written
    /// to be safe to call more than once. Here, the player and everything
    /// pushed on top of it (`PlayerRoute`) live in one
    /// `FullScreenDestination.player` presentation instead of stack
    /// entries, so "pop everything player-owned" is just dismissing that
    /// presentation — idempotent for the same reason Dart's guard is:
    /// dismissing an already-dismissed presentation is a no-op.
    func popPlayerScreens() {
        guard presentedFullScreen == .player else { return }
        dismissFullScreen()
    }

    func sheetPresented() {
        openSheetCount += 1
    }

    func sheetDismissed() {
        openSheetCount = max(0, openSheetCount - 1)
    }

    // MARK: - Dock visibility (T17)

    /// `canShowBottomNavBar(routeName)` (`lib/routes/routes.dart`) plus the
    /// sheet-open rule applied on top of it in
    /// `_OurAdaptiveScaffoldState`/`_Ios26BodyWrapper`. The ad-break rule
    /// that same route checker also guards
    /// (`DashboardNavBloc._hideNavBarForAdBreak`) is covered for free here:
    /// player-owned routes all live behind `FullScreenDestination.player`,
    /// which already covers this dock completely regardless of this value.
    /// Route-only half of `isTabBarVisible` for the system tab bar, which a
    /// presented sheet already covers by itself (`hidesTabBar` per route).
    func routeAllowsTabBar(for tab: AppTab) -> Bool {
        tabPaths[tab]?.last?.hidesTabBar != true
    }

    var isTabBarVisible: Bool {
        guard openSheetCount == 0 else { return false }
        return tabPaths[selectedTab]?.last?.hidesTabBar != true
    }

    /// `canShowMusicPlayerBottom(routeName)`, AND-ed with the two further
    /// ground-truth factors `DashboardNavBloc` folds in that no route table
    /// can express on its own: `_hiddenPlayerTabs`
    /// (`AppTab.alwaysHidesMiniPlayer`) and `_canShowPlayer`
    /// (`isPlaybackActive`).
    var isMiniPlayerVisible: Bool {
        guard isPlaybackActive, openSheetCount == 0, !selectedTab.alwaysHidesMiniPlayer else {
            return false
        }
        return tabPaths[selectedTab]?.last?.hidesMiniPlayer != true
    }
}
