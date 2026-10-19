import Foundation
@testable import Hallelujah

extension Membership {
    /// Built by decoding JSON because `Subscription` has a custom
    /// `init(from:)` (so no memberwise init) — which also exercises the same
    /// decode path the real `/users/me` response takes.
    static func fixture(
        role: String = "owner",
        status: String = "active",
        endsInDays days: Int = 30,
        maxMembers: Int = 1
    ) throws -> Membership {
        let formatter = ISO8601DateFormatter()
        let now = Date()
        let json = """
        {
          "role": "\(role)",
          "subscription": {
            "id": "sub-1",
            "planId": "plan-1",
            "planName": "Premium",
            "ownerId": "user-1",
            "status": "\(status)",
            "startDate": "\(formatter.string(from: now.addingTimeInterval(-86_400)))",
            "endDate": "\(formatter.string(from: now.addingTimeInterval(Double(days) * 86_400)))",
            "autoRenew": true,
            "plan": { "maxMembers": \(maxMembers) },
            "provider": { "provider": "apple" }
          }
        }
        """
        return try JSONDecoder().decode(Membership.self, from: Data(json.utf8))
    }
}
