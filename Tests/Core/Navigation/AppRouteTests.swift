import Testing
@testable import GHallelujah

struct AppRouteTests {
    @Test func fullScreenRoutesHideTabBarAndMiniPlayer() {
        #expect(AppRoute.subscriptionPlans.hidesTabBar)
        #expect(AppRoute.subscriptionPlans.hidesMiniPlayer)
        #expect(AppRoute.faqs.hidesTabBar)
    }

    @Test func settingsHidesNeither() {
        #expect(!AppRoute.settings.hidesTabBar)
        #expect(!AppRoute.settings.hidesMiniPlayer)
    }

    @Test func downloadsKeepsTheTabBar() {
        #expect(!AppRoute.downloads.hidesTabBar)
    }
}
