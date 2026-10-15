import Foundation

/// `GET /song/:id/related?limit=&excludeId=` (`RelatedContentService._fetch`,
/// `lib/services/related_content_service.dart`). Throws on any failure; the
/// service above it turns failures into an empty result.
protocol RelatedContentRepository: Sendable {
    func fetchRelated(songId: String, excludeId: String?, limit: Int) async throws -> RelatedContent
}
