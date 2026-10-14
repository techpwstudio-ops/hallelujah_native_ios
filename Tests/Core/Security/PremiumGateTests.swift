import Testing
@testable import GHallelujah

struct PremiumGateTests {
    private func makeGate(membership: Membership?) async -> PremiumGate {
        let store = MembershipStore(keyValueStore: InMemoryKeyValueStore())
        await store.setMembership(membership)
        return PremiumGate(membershipStore: store)
    }

    @Test func noMembershipMeansNoPremiumAndAds() async {
        let gate = await makeGate(membership: nil)
        #expect(await !gate.hasPremium)
        #expect(await gate.showsAds)
    }

    @Test func activeSubscriptionUnlocksEveryFeatureAndHidesAds() async throws {
        let gate = await makeGate(membership: try Membership.fixture(endsInDays: 30))
        #expect(await gate.hasPremium)
        #expect(await !gate.showsAds)
        for feature in PremiumFeature.allCases {
            #expect(await gate.allows(feature))
        }
    }

    @Test func expiredSubscriptionLocksEveryFeature() async throws {
        let gate = await makeGate(membership: try Membership.fixture(endsInDays: -2))
        #expect(await !gate.hasPremium)
        #expect(await gate.showsAds)
        for feature in PremiumFeature.allCases {
            #expect(await !gate.allows(feature))
        }
    }

    @Test func cancelledButUnexpiredSubscriptionStaysPremium() async throws {
        let gate = await makeGate(membership: try Membership.fixture(status: "cancelled", endsInDays: 5))
        #expect(await gate.hasPremium)
    }

    @Test func gateFollowsMembershipChangesWithoutCaching() async throws {
        let store = MembershipStore(keyValueStore: InMemoryKeyValueStore())
        let gate = PremiumGate(membershipStore: store)
        #expect(await !gate.hasPremium)

        await store.setMembership(try Membership.fixture(endsInDays: 30))
        #expect(await gate.hasPremium)

        await store.clear()
        #expect(await !gate.hasPremium)
    }
}
