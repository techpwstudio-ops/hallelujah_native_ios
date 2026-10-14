import Foundation
import Testing
@testable import GHallelujah

/// `FreeTrial.fromJson` (`subscription_plan_model.dart`): months/days as
/// numbers or numeric strings; an all-zero or malformed block is "no trial".
struct PlanFreeTrialTests {
    private func decodePlan(freeTrial: String?) throws -> SubscriptionPlan {
        let trial = freeTrial.map { ",\\"freeTrial\\":\\($0)" } ?? ""
        let json = """
        {"id":"p1","name":"Premium","billingCycle":"monthly"\\(trial)}
        """
        return try JSONDecoder().decode(SubscriptionPlan.self, from: Data(json.utf8))
    }

    @Test func decodesNumericCounts() throws {
        let plan = try decodePlan(freeTrial: #"{"months":1,"days":14}"#)
        #expect(plan.freeTrial?.months == 1)
        #expect(plan.freeTrial?.days == 14)
    }

    @Test func decodesStringCounts() throws {
        let plan = try decodePlan(freeTrial: #"{"months":"0","days":"7"}"#)
        #expect(plan.freeTrial == PlanFreeTrial(months: 0, days: 7))
    }

    @Test func zeroOrNegativeCountsMeanNoTrial() throws {
        #expect(try decodePlan(freeTrial: #"{"months":0,"days":0}"#).freeTrial == nil)
        #expect(try decodePlan(freeTrial: #"{"months":-2,"days":-1}"#).freeTrial == nil)
        #expect(PlanFreeTrial(months: 0, days: 0) == nil)
    }

    @Test func nullOrMissingBlockMeansNoTrial() throws {
        #expect(try decodePlan(freeTrial: "null").freeTrial == nil)
        #expect(try decodePlan(freeTrial: nil).freeTrial == nil)
    }

    @Test func planCopyReadsTheDomainField() throws {
        let plan = try decodePlan(freeTrial: #"{"months":0,"days":14}"#)
        let trial = try #require(PlanCopy.trial(for: plan))
        #expect(PlanCopy.freeTrialPeriod(trial) == "2 Weeks")
        #expect(PlanCopy.freeTrialHeadline(trial) == "2 Weeks Free")
    }
}
