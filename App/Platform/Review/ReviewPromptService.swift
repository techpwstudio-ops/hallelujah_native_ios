import Foundation
import StoreKit
import UIKit

/// How much a device has used the app, as far as the review prompt cares
/// (`ReviewEngagement`, `lib/services/review_prompt_service.dart`, `ai` branch).
struct ReviewEngagement: Codable, Sendable, Equatable {
    /// Distinct calendar days the app was brought to the foreground.
    var activeDays = 0
    /// `yyyy-MM-dd` of the most recent counted day; what makes a second open on
    /// the same day not count twice.
    var lastActiveDay: String?
    /// Listens long enough to count as the user actually using the app.
    var qualifiedListens = 0

    func afterOpening(on day: String) -> ReviewEngagement {
        guard day != lastActiveDay else { return self }
        return ReviewEngagement(activeDays: activeDays + 1, lastActiveDay: day, qualifiedListens: qualifiedListens)
    }

    func afterQualifiedListen() -> ReviewEngagement {
        ReviewEngagement(activeDays: activeDays, lastActiveDay: lastActiveDay, qualifiedListens: qualifiedListens + 1)
    }
}

/// What counts as "uses the app most of the time". The prompt is a one-shot per
/// device, so the bar is deliberately high: better to wait for a clearly
/// engaged listener than to spend the only request on a curious one.
struct ReviewPromptPolicy: Sendable {
    /// Distinct days the app has been opened.
    var minActiveDays = 5
    /// Listens of at least `minListenMs` — the same 30 s bar streaming
    /// services use for "a play".
    var minQualifiedListens = 20
    var minListenMs = 30_000
    /// A listen that got this far through the track counts as finishing it, the
    /// positive moment the prompt is tied to.
    var finishedFraction = 0.8

    func isQualifiedListen(listenedMs: Int) -> Bool { listenedMs >= minListenMs }

    func isFinished(listenedMs: Int, totalMs: Int) -> Bool {
        totalMs > 0 && Double(listenedMs) >= Double(totalMs) * finishedFraction
    }

    func isEligible(_ engagement: ReviewEngagement) -> Bool {
        engagement.activeDays >= minActiveDays && engagement.qualifiedListens >= minQualifiedListens
    }
}

/// Asks the listener for an App Store rating — once, ever.
///
/// **The guarantee is "requested at most once per device", not "asked only
/// people who have not reviewed".** iOS never says whether the dialog was shown
/// or a review submitted, so a user who has already reviewed cannot be
/// detected; remembering that we asked is the closest the platform allows.
///
/// Flow: `onForeground` counts distinct active days, `onListenEnded` counts
/// qualified listens. Once `ReviewPromptPolicy` is satisfied, the next listen
/// played through to the end schedules the request a few seconds later; it
/// fires only if the app is still in the foreground and nothing (an ad break)
/// is in the way. A request held back is not spent — the next finished song
/// tries again.
///
/// Persistence is `UserDefaults` (never wiped on sign-out here, unlike Flutter's
/// Hive box which is why Flutter used secure storage).
@MainActor
final class ReviewPromptService {
    static let engagementKey = "review_prompt_engagement"
    static let requestedKey = "review_prompt_requested"

    private let store: any KeyValueStoring
    private let policy: ReviewPromptPolicy
    private let requestReview: @MainActor () -> Void
    private let isForeground: @MainActor () -> Bool
    private let now: () -> Date
    private let settleDelay: Duration
    private let logger = AppLogger(category: .app)

    /// Set by the app layer: true while something must not be interrupted (an
    /// ad break).
    var isBlocked: @MainActor () -> Bool = { false }

    private(set) var engagement: ReviewEngagement
    private(set) var requested: Bool
    private var timer: Task<Void, Never>?

    init(
        store: any KeyValueStoring,
        policy: ReviewPromptPolicy = ReviewPromptPolicy(),
        settleDelay: Duration = .seconds(4),
        now: @escaping () -> Date = Date.init,
        isForeground: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active },
        requestReview: @escaping @MainActor () -> Void = ReviewPromptService.systemRequestReview
    ) {
        self.store = store
        self.policy = policy
        self.settleDelay = settleDelay
        self.now = now
        self.isForeground = isForeground
        self.requestReview = requestReview
        requested = store.bool(forKey: Self.requestedKey)
        // A missing or unreadable value is a fresh start, never an error:
        // losing the counters only delays the prompt.
        engagement = store.data(forKey: Self.engagementKey)
            .flatMap { try? JSONDecoder().decode(ReviewEngagement.self, from: $0) } ?? ReviewEngagement()
    }

    /// Call whenever the app comes to the foreground (launch and resume).
    func onForeground() {
        guard !requested else { return }
        let next = engagement.afterOpening(on: Self.dayKey(now()))
        guard next != engagement else { return }
        engagement = next
        persist()
    }

    /// Call when a play session ends. `totalDurationMs` is 0 when unknown.
    func onListenEnded(listenedMs: Int, totalDurationMs: Int) {
        guard !requested else { return }
        if policy.isQualifiedListen(listenedMs: listenedMs) {
            engagement = engagement.afterQualifiedListen()
            persist()
        }
        if policy.isFinished(listenedMs: listenedMs, totalMs: totalDurationMs) {
            schedule()
        }
    }

    private func schedule() {
        guard timer == nil, policy.isEligible(engagement) else { return }
        timer = Task { [weak self, settleDelay] in
            try? await Task.sleep(for: settleDelay)
            guard !Task.isCancelled, let self else { return }
            self.timer = nil
            self.maybeRequest()
        }
    }

    /// Requests the review if every condition holds right now. Internal so
    /// tests can drive it without waiting on `settleDelay`.
    func maybeRequest() {
        guard !requested, policy.isEligible(engagement) else { return }
        guard isForeground(), !isBlocked() else {
            logger.debug("review prompt held back: not a good moment")
            return
        }
        // Spend the shot before asking, and never hand it back: "at most once"
        // is the rule that matters.
        requested = true
        store.setBool(true, forKey: Self.requestedKey)
        logger.info("requesting store review (activeDays=\(engagement.activeDays), qualifiedListens=\(engagement.qualifiedListens))")
        requestReview()
    }

    /// Cancels a scheduled request. For tests and teardown.
    func cancel() {
        timer?.cancel()
        timer = nil
    }

    private func persist() {
        store.setData(try? JSONEncoder().encode(engagement), forKey: Self.engagementKey)
    }

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func systemRequestReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }
        AppStore.requestReview(in: scene)
    }
}
