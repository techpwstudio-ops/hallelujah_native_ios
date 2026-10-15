import Foundation

final class RemoteSupportRepository: SupportRepository {
    private let client: HTTPClient

    init(client: HTTPClient) {
        self.client = client
    }

    func fetchFAQs() async throws -> [FAQItem] {
        let response = try await client.send(.faqs)
        guard response.statusCode == 200 else {
            throw SupportRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(FAQListResponseDTO.self, from: response.data)
        return decoded.data.map { FAQItem(id: $0.id, question: $0.question, answer: $0.answer) }
    }

    func submitFeedback(title: String, description: String) async throws -> SubmitFeedbackResult {
        let body = try JSONEncoder().encode(SubmitFeedbackRequest(title: title, description: description))
        let response = try await client.send(.sendFeedback, body: body)
        let decoded = try? JSONDecoder().decode(FeedbackResponseDTO.self, from: response.data)
        return SubmitFeedbackResult(succeeded: response.statusCode == 200 || response.statusCode == 201, message: decoded?.message)
    }
}

private struct FAQListResponseDTO: Decodable {
    let data: [FAQDTO]
}

/// Defensive per-field decode, same posture as `FaqModel.fromJson`
/// (`faqProvider.dart`) tolerating a malformed row rather than failing the
/// whole list — one bad FAQ shouldn't blank the screen.
private struct FAQDTO: Decodable {
    let id: String
    let question: String
    let answer: String

    private enum CodingKeys: String, CodingKey { case id, question, answer }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? ""
        question = (try? container.decode(String.self, forKey: .question)) ?? ""
        answer = (try? container.decode(String.self, forKey: .answer)) ?? ""
    }
}

private struct SubmitFeedbackRequest: Encodable {
    let title: String
    let description: String
}

private struct FeedbackResponseDTO: Decodable {
    let message: String?
}
