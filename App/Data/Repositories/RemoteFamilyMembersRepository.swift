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

    func resendInvitation(inviteId: String) async throws -> String {
        let body = try JSONEncoder().encode(ResendFamilyInviteRequest(inviteId: inviteId))
        let response = try await client.send(.resendFamilyMemberInvite, body: body)
        guard response.statusCode == 200 else {
            throw SubscriptionError(statusCode: response.statusCode, data: response.data)
        }
        let decoded = try JSONDecoder().decode(ResendFamilyInviteResponseDTO.self, from: response.data)
        return decoded.data.status
    }

    func cancelInvitation(inviteId: String) async throws {
        let response = try await client.send(.cancelFamilyMemberInvite(inviteId: inviteId))
        guard response.statusCode == 200 else {
            throw SubscriptionError(statusCode: response.statusCode, data: response.data)
        }
    }

    func removeMember(memberId: String) async throws {
        let response = try await client.send(.removeFamilyMember(memberId: memberId))
        guard response.statusCode == 200 else {
            throw SubscriptionError(statusCode: response.statusCode, data: response.data)
        }
    }
}
