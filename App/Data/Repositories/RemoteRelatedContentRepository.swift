import Foundation

enum RelatedContentRepositoryError: Error, Sendable, Equatable {
    case unexpectedStatus(Int)
}

extension Endpoint {
    /// `getRelatedContentApi` — `/song/:id/related`; `limit` is 1-20 and
    /// `excludeId` is the playlist or creator already playing.
    static func relatedContent(songId: String, excludeId: String?, limit: Int) -> Endpoint {
        var path = "/song/\(songId)/related?limit=\(limit)"
        if let excludeId, !excludeId.isEmpty {
            var allowed = CharacterSet.urlQueryAllowed
            allowed.remove(charactersIn: "&=+")
            path += "&excludeId=\(excludeId.addingPercentEncoding(withAllowedCharacters: allowed) ?? excludeId)"
        }
        return .get(path)
    }
}

/// Wire shape: `{data: {kind, items: [{id, title|name, reason, image, imageVariants}]}}`.
struct RelatedContentResponseDTO: Decodable, Sendable {
    let data: Payload?

    struct Payload: Decodable, Sendable {
        let kind: String?
        let items: [Row]?
    }

    struct Row: Decodable, Sendable {
        let id: String
        let title: String?
        let name: String?
        let reason: String?
        let image: String?
        let imageVariants: String?

        private enum CodingKeys: String, CodingKey { case id, title, name, reason, image, imageVariants }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Dart stringifies the id (`map['id'].toString()`).
            if let string = try? container.decode(String.self, forKey: .id) {
                id = string
            } else {
                id = String(try container.decode(Int.self, forKey: .id))
            }
            title = try? container.decodeIfPresent(String.self, forKey: .title)
            name = try? container.decodeIfPresent(String.self, forKey: .name)
            reason = try? container.decodeIfPresent(String.self, forKey: .reason)
            image = try? container.decodeIfPresent(String.self, forKey: .image)
            imageVariants = try? container.decodeIfPresent(String.self, forKey: .imageVariants)
        }
    }

    func toDomain() -> RelatedContent {
        guard let data else { return .empty }
        let kind = RelatedItemKind(wire: data.kind)
        let items = (data.items ?? []).map {
            RelatedItem(
                kind: kind,
                id: $0.id,
                title: $0.title ?? $0.name ?? "",
                reason: $0.reason,
                image: $0.image,
                imageVariants: $0.imageVariants
            )
        }
        return RelatedContent(kind: kind, items: items)
    }
}

final class RemoteRelatedContentRepository: RelatedContentRepository {
    private let client: HTTPClient

    init(client: HTTPClient) {
        self.client = client
    }

    func fetchRelated(songId: String, excludeId: String?, limit: Int) async throws -> RelatedContent {
        let response = try await client.send(.relatedContent(songId: songId, excludeId: excludeId, limit: limit))
        guard response.statusCode == 200 else {
            throw RelatedContentRepositoryError.unexpectedStatus(response.statusCode)
        }
        return try JSONDecoder().decode(RelatedContentResponseDTO.self, from: response.data).toDomain()
    }
}
