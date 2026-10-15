import Foundation

/// `getSubscriptionMembers` response envelope — `{data: FamilyMembers}`.
struct FamilyMembersResponseDTO: Decodable, Sendable {
    let data: FamilyMembers
}

/// `sendInvitation`'s success body — `{data: InviteModel}`
/// (`manage_premium_service.dart`'s `res.data['data']`, fed straight into
/// `InviteModel.fromJson`). No `message` field is read on this branch in
/// Dart either (it shows a static `showInviteSentSheet` instead).
struct SendFamilyInviteResponseDTO: Decodable, Sendable {
    let data: FamilyInvite
}

/// `resendInvitation`'s success body — `{message, data: {status}}`.
struct ResendFamilyInviteResponseDTO: Decodable, Sendable {
    let message: String?
    let data: ResendFamilyInviteData
}

struct ResendFamilyInviteData: Decodable, Sendable {
    let status: String
}

/// `sendInvitation` request body — `{identifier}`.
struct SendFamilyInviteRequest: Encodable {
    let identifier: String
}

/// `resendInvitation` request body — `{inviteId}`.
struct ResendFamilyInviteRequest: Encodable {
    let inviteId: String
}

/// Any family endpoint's `{message}` (Dart toasts `res.data['message']`).
struct FamilyMessageResponseDTO: Decodable, Sendable {
    let message: String?
}

/// `acceptInvitation`'s success body — `{message, data: <membership>}`.
struct AcceptFamilyInviteResponseDTO: Decodable, Sendable {
    let message: String?
    let data: Membership?
}
