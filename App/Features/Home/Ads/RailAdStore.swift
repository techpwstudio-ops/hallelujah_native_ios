import Foundation
import Observation

/// What the home feed's rails remember about their square ad slots, for as long
/// as the feed lives (`reset()` ends that — pull-to-refresh). Ports
/// `RailAdStore` (`lib/ads/rail_ad_store.dart`).
///
/// WHY THIS EXISTS, rather than each slot view holding its own ad: a lazy rail
/// drops slots scrolled off screen and rebuilds them on the way back. A slot
/// that kept its ad in its own `@State` would ask the server again every time —
/// reserving budget, swapping the creative under the listener's thumb and
/// confirming a second impression. So the ad lives here, keyed by the slot's
/// POSITION (`RailAdLayout.slotIdAt`), and a rebuilt slot reads it back.
///
/// Rules it enforces: one request per slot at a time (and one per feed session
/// unless the ad went unseen long enough for its token to near expiry); one
/// interval per feed session; one campaign per page; an ad is only a slot's ad
/// once its artwork has loaded; one impression per ad.
@MainActor
@Observable
final class RailAdStore {
    /// What one slot is holding.
    private final class Entry {
        var ad: AdCreative?
        var settled = false
        var impressionSent = false
        var dismissed = false
        var settledAt: Date?
        var inFlight: Task<Void, Never>?
    }

    /// The backend placement the rail cards are served from — `image_square`.
    nonisolated static let placement = "image_square"
    /// Organic items between ads until the server has reported its own number.
    nonisolated static let defaultInterval = 4
    /// How long an ad that nobody has seen may sit before it is asked for
    /// again. Under the backend's 600 s impression-token lifetime.
    nonisolated static let staleAfter: TimeInterval = 5 * 60

    /// The one store the home feed uses.
    static let shared = RailAdStore(
        serve: {
            let ads: AdsRepository = DependencyContainer.current.resolve()
            return await ads.serveThroughGate(placement: RailAdStore.placement)
        },
        learnedInterval: {
            let ads: AdsRepository = DependencyContainer.current.resolve()
            return ads.pacingEveryN(RailAdStore.placement)
        }
    )

    /// Bumped by `reset()`. A slot view keys its load task on it, so slots still
    /// on screen after a pull-to-refresh ask again.
    private(set) var generation = 0

    private let serve: () async -> AdCreative?
    private let learnedInterval: () -> Int?
    private let prepare: (AdCreative) async -> Bool
    private let now: () -> Date
    @ObservationIgnored private var slots: [String: Entry] = [:]
    /// campaignKey -> the slot showing it, for the one-campaign-per-page rule.
    @ObservationIgnored private var campaignOwner: [String: String] = [:]
    @ObservationIgnored private var resolvedInterval: Int?

    init(
        serve: @escaping () async -> AdCreative?,
        learnedInterval: @escaping () -> Int?,
        prepare: @escaping (AdCreative) async -> Bool = { await AdArtwork.warm($0) },
        now: @escaping () -> Date = Date.init
    ) {
        self.serve = serve
        self.learnedInterval = learnedInterval
        self.prepare = prepare
        self.now = now
    }

    /// Organic items between two ads, for every rail of this feed session.
    /// Resolved once, by whichever rail lays out first.
    var interval: Int {
        if let resolvedInterval { return resolvedInterval }
        let learned = learnedInterval()
        let value = learned.map { $0 > 0 ? $0 : Self.defaultInterval } ?? Self.defaultInterval
        resolvedInterval = value
        return value
    }

    /// How `railId`'s list of `organicCount` items is laid out. A nil `railId`
    /// is a rail that carries no ads.
    func layoutFor(_ railId: String?, _ organicCount: Int) -> RailAdLayout {
        guard let railId else { return RailAdLayout(organicCount: organicCount) }
        return RailAdLayout(organicCount: organicCount, railId: railId, interval: interval)
    }

    /// The creative `slotId` should draw right now, or nil to draw nothing.
    func adFor(_ slotId: String) -> AdCreative? {
        guard let entry = slots[slotId], entry.settled, !entry.dismissed else { return nil }
        return entry.ad
    }

    /// Whether `load` would start a request: never asked, or its unseen ad has
    /// gone stale.
    func needsLoad(_ slotId: String) -> Bool {
        guard let entry = slots[slotId] else { return true }
        return needsLoad(entry)
    }

    private func needsLoad(_ entry: Entry) -> Bool {
        if entry.inFlight != nil { return false }
        if !entry.settled { return true }
        // Shown or closed: leave it.
        if entry.impressionSent || entry.dismissed { return false }
        // Never seen — an ad, or a no-fill worth asking about again.
        guard let settledAt = entry.settledAt else { return true }
        return now().timeIntervalSince(settledAt) > Self.staleAfter
    }

    /// Fills `slotId` if it needs it, and returns when the slot has settled. A
    /// second caller while a request is out awaits that same request. Never
    /// throws — an ads problem is a collapsed slot, not an error.
    func load(_ slotId: String) async {
        let entry: Entry
        if let existing = slots[slotId] {
            entry = existing
        } else {
            entry = Entry()
            slots[slotId] = entry
        }
        if let pending = entry.inFlight {
            await pending.value
            return
        }
        guard needsLoad(entry) else { return }

        // A creative going stale is dropped rather than shown while its
        // replacement loads.
        release(slotId, entry.ad)
        entry.ad = nil

        let task = Task { [weak self] in
            await self?.fetch(slotId, entry)
        }
        entry.inFlight = task
        await task.value
        entry.inFlight = nil
    }

    private func fetch(_ slotId: String, _ entry: Entry) async {
        var ad = await serve()
        if let candidate = ad, !(await prepare(candidate)) { ad = nil }

        // `reset()` while the request was out: this slot belongs to a feed
        // that no longer exists.
        guard slots[slotId] === entry else { return }

        if let candidate = ad, !claim(candidate.campaignKey, slotId) { ad = nil }

        entry.ad = ad
        entry.settled = true
        entry.settledAt = now()
        entry.impressionSent = false
    }

    private func claim(_ campaignKey: String, _ slotId: String) -> Bool {
        if let owner = campaignOwner[campaignKey], owner != slotId { return false }
        campaignOwner[campaignKey] = slotId
        return true
    }

    private func release(_ slotId: String, _ ad: AdCreative?) {
        guard let ad, campaignOwner[ad.campaignKey] == slotId else { return }
        campaignOwner.removeValue(forKey: ad.campaignKey)
    }

    /// True exactly once per served ad — the caller confirms the impression
    /// when it is. Takes the creative the caller actually drew, so a late
    /// confirmation is not spent on whatever the slot has been handed since.
    func claimImpression(_ slotId: String, _ ad: AdCreative) -> Bool {
        guard let entry = slots[slotId], !entry.impressionSent else { return false }
        guard entry.ad?.impressionToken == ad.impressionToken else { return false }
        entry.impressionSent = true
        return true
    }

    /// The listener closed or rejected the ad in `slotId`; the slot stays
    /// collapsed for the rest of the feed.
    func dismiss(_ slotId: String) {
        slots[slotId]?.dismissed = true
    }

    /// Forgets every slot and the interval, so the next feed asks afresh.
    func reset() {
        slots.removeAll()
        campaignOwner.removeAll()
        resolvedInterval = nil
        generation += 1
    }
}

extension AdCreative {
    /// `AdCreative.campaignKey` — the advertiser's campaign, or, for a company
    /// ad (which belongs to none), its own id with a prefix so the two id
    /// spaces cannot collide.
    var campaignKey: String { isCompany ? "company:\(adId)" : campaignId }
}
