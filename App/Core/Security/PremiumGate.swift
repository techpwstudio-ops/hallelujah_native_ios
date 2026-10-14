import Foundation

/// Features the Flutter app restricts to paying subscribers. Ports every
/// `OurSession.instance.shouldBlockPremiumAccess` call site
/// (`song_menu_sheet.dart`: sleep timer, download; `settings_screen.dart`:
/// audio quality; `ads_repository.dart`: ads). AI chat/voice has no premium
/// check in the Flutter app, so none is invented here.
enum PremiumFeature: Sendable, CaseIterable {
    /// Saving songs for offline playback.
    case downloads
    /// The "Audio Quality" preference row.
    case audioQualitySettings
    /// The player's sleep timer.
    case sleepTimer
}

/// T65 — the single source of truth for "is this listener premium, and so
/// what are they allowed". Every gate in the app asks this type; nothing else
/// reads `Membership`/`Subscription.isActive` to decide a feature. Ports
/// `OurSession.shouldBlockPremiumAccess` (`lib/utils/session.dart`), inverted
/// to the positive question callers actually ask.
///
/// Stateless: it reads `MembershipStore` on every call, so a purchase,
/// restore, expiry or sign-out is reflected the next time anything asks —
/// there is no cached verdict to go stale.
struct PremiumGate: Sendable {
    private let membershipStore: MembershipStore

    init(membershipStore: MembershipStore) {
        self.membershipStore = membershipStore
    }

    /// An active (not yet expired) subscription — owner or family member.
    var hasPremium: Bool {
        get async { await membershipStore.membership?.subscription.isActive == true }
    }

    func allows(_ feature: PremiumFeature) async -> Bool {
        await hasPremium
    }

    /// Paying subscribers never see ads (`ads_repository.dart`'s
    /// `_blockedReason`).
    var showsAds: Bool {
        get async { await !hasPremium }
    }
}
