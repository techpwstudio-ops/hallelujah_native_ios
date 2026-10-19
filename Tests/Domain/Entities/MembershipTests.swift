import Foundation
import Testing
@testable import Hallelujah

struct MembershipTests {
    @Test func subscriptionEndingInTheFutureIsActive() throws {
        let subscription = try Membership.fixture(endsInDays: 10).subscription
        #expect(subscription.isActive)
        #expect(!subscription.isExpired)
    }

    @Test func subscriptionThatEndedIsNotActive() throws {
        let subscription = try Membership.fixture(endsInDays: -1).subscription
        #expect(!subscription.isActive)
        #expect(subscription.isExpired)
    }

    @Test func remainingDaysNeverGoesNegative() throws {
        #expect(try Membership.fixture(endsInDays: -5).subscription.remainingDays == 0)
        #expect(try Membership.fixture(endsInDays: 10).subscription.remainingDays >= 9)
    }

    @Test func cancelledStatusIsDetected() throws {
        #expect(try Membership.fixture(status: "cancelled").subscription.isCanceled)
        #expect(try !Membership.fixture(status: "active").subscription.isCanceled)
    }

    @Test func displayStatusReflectsState() throws {
        #expect(try Membership.fixture(endsInDays: 30).subscription.displayStatus == "Premium")
        #expect(try Membership.fixture(status: "cancelled", endsInDays: 30).subscription.displayStatus.hasPrefix("Premium (Ends in"))
        #expect(try Membership.fixture(endsInDays: -1).subscription.displayStatus == "Explore Premium")
    }

    @Test func ownerRoleAndPlanDetailsDecode() throws {
        let membership = try Membership.fixture(role: "owner", maxMembers: 5)
        #expect(membership.isOwner)
        #expect(membership.subscription.maxMembers == 5)
        #expect(membership.subscription.providerName == "apple")
        #expect(try !Membership.fixture(role: "member").isOwner)
    }
}
