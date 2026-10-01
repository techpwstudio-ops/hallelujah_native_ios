import Foundation

enum NotificationTopicsRepositoryError: Error, Sendable, Equatable {
    case unexpectedStatus(Int)
}

final class RemoteNotificationTopicsRepository: NotificationTopicsRepository {
    private let client: HTTPClient

    init(client: HTTPClient) {
        self.client = client
    }

    func fetchEligibleTopics(reachLanguage: String) async throws -> [NotificationTopic] {
        let response = try await client.send(.dashboardInit)
        guard response.statusCode == 200 else {
            throw NotificationTopicsRepositoryError.unexpectedStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(DashboardInitTopicsDTO.self, from: response.data)
        let want = reachLanguage.trimmingCharacters(in: .whitespaces).lowercased()

        return decoded.topics.map { $0.toDomain() }.filter { topic in
            // `nil`/empty language = global topic, everyone gets it — the
            // exact `lang == null || lang.isEmpty || lang == want` guard
            // `syncLanguageScopedTopics`/`eligibleTopics()` apply
            // (`fcm_service.dart`).
            guard let language = topic.language?.trimmingCharacters(in: .whitespaces).lowercased(),
                  !language.isEmpty else {
                return true
            }
            return language == want
        }
    }
}
