import Testing
@testable import Hallelujah

struct PremiumInviteCoordinatorTests {
    @Test func processingStageIsNotDismissible() {
        #expect(!PremiumInviteCoordinator.Stage.processing(title: "t", description: "d").isDismissible)
        #expect(PremiumInviteCoordinator.Stage.success.isDismissible)
    }

    @Test func allStagesShareOneSheetIdentity() {
        let invite = PremiumInviteCoordinator.PendingInvite(inviteId: "1", inviterName: "A", planName: "Family")
        #expect(PremiumInviteCoordinator.Stage.invite(invite).id == PremiumInviteCoordinator.Stage.success.id)
    }
}
