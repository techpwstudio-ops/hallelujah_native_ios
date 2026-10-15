import Foundation

/// `ManagePremiumService`'s family-member call sites against the real
/// `/premium/subscription/*` contract. Errors reuse `SubscriptionError`
/// (`SubscriptionDTOs.swift`) rather than a new type — same `/premium/*`
/// backend, same `{message}` error-body shape, confirmed against the
/// controller responses these endpoints share with T61's.
final class RemoteFamilyMembersRepository: FamilyMembersRepository {
    private let client: HTTPClient

    init(client: HTTPClient) {
        self.client = client
    }

    func fetchMembers() async throws -> FamilyMembers {
        let response = try await client.send(.familyMembers)
        guard response.statusCode == 200 else {
            throw SubscriptionError(statusCode: response.statusCode, data: response.data)
        }
        let decoded = try JSONDecoder().decode(FamilyMembersResponseDTO.self, from: response.data)
        return decoded.data
    }

    func sendInvitation(identifier: String) async throws -> FamilyInvite {
        let body = try JSONEncoder().encode(SendFamilyInviteRequest(identifier: identifier))
        let response = try await client.send(.sendFamilyMemberInvite, body: body)
        guard response.statusCode == 200 else {
            throw SubscriptionError(statusCode: response.statusCode, data: response.data)
        }
        let decoded = try JSONDecoder().decode(SendFamilyInviteResponseDTO.self, from: response.data)
        return decoded.data
    }

    func resendInvitation(inviteId: String) async throws -> FamilyInviteResendResult {
        let body = try JSONEncoder().encode(ResendFamilyInviteRequest(inviteId: inviteId))
        let response = try await client.send(.resendFamilyMemberInvite, body: body)
        guard response.statusCode == 200 else {
            throw SubscriptionError(statusCode: response.statusCode, data: response.data)
        }
        let decoded = try JSONDecoder().decode(ResendFamilyInviteResponseDTO.self, from: response.data)
        return FamilyInviteResendResult(status: decoded.data.status, message: decoded.message)
    }

    func cancelInvitation(inviteId: String) async throws -> String? {
        let response = try await client.send(.cancelFamilyMemberInvite(inviteId: inviteId))
        guard response.statusCode == 200 else {
            throw SubscriptionError(statusCode: response.statusCode, data: response.data)
        }
        return Self.message(in: response.data)
    }

    func removeMember(memberId: String) async throws -> String? {
        let response = try await client.send(.removeFamilyMember(memberId: memberId))
        guard response.statusCode == 200 else {
            throw SubscriptionError(statusCode: response.statusCode, data: response.data)
        }
        return Self.message(in: response.data)
    }

    func acceptInvitation(inviteId: String) async throws -> FamilyInviteActionResult {
        let body = try JSONEncoder().encode(ResendFamilyInviteRequest(inviteId: inviteId))
        let response = try await client.send(.acceptFamilyMemberInvite, body: body)
        guard response.statusCode == 200 else {
            throw SubscriptionError(statusCode: response.statusCode, data: response.data)
        }
        let decoded = try? JSONDecoder().decode(AcceptFamilyInviteResponseDTO.self, from: response.data)
        return FamilyInviteActionResult(message: decoded?.message, membership: decoded?.data)
    }

    func declineInvitation(inviteId: String) async throws -> FamilyInviteActionResult {
        let body = try JSONEncoder().encode(ResendFamilyInviteRequest(inviteId: inviteId))
        let response = try await client.send(.declineFamilyMemberInvite, body: body)
        guard response.statusCode == 200 else {
            throw SubscriptionError(statusCode: response.statusCode, data: response.data)
        }
        return FamilyInviteActionResult(message: Self.message(in: response.data), membership: nil)
    }

    private static func message(in data: Data) -> String? {
        (try? JSONDecoder().decode(FamilyMessageResponseDTO.self, from: data))?.message
    }
}
