import Foundation

/// T55 (offline bible and search) — `src/routes/user/book.routes.js`'s
/// `/book/search` and `/book/snapshot/trigger`. See `BibleOfflineRepository`'s
/// doc comment for why this is a separate repository from `RemoteBibleRepository`.
final class RemoteBibleOfflineRepository: BibleOfflineRepository {
    private let client: HTTPClient
    /// Direct `URLSession`, not `client`: the CDN snapshot is a fully-
    /// qualified, unauthenticated public URL — wrong shape for `HTTPClient`,
    /// which builds JSON-API requests relative to `apiBaseURL`/`proxyBaseURL`
    /// with a bearer token attached. Same line `ArtworkImageCache` already
    /// draws for CDN image URLs (see its own doc comment on this exact
    /// choice); Dart draws it identically (`CachedNetworkImageProvider`/
    /// `S3Service` never go through `DioApi` for a direct CloudFront URL).
    private let urlSession: URLSession
    private let cdnHost: String
    private let logger = AppLogger(category: .content)

    init(client: HTTPClient, cdnHost: String, urlSession: URLSession = .shared) {
        self.client = client
        self.cdnHost = cdnHost
        self.urlSession = urlSession
    }

    func search(query: String, languageName: String, limit: Int) async throws -> BibleSearchResponse {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty(query: trimmed) }

        let response: HTTPResponse
        do {
            response = try await client.send(.bookSearch(query: trimmed, languageName: languageName, limit: limit))
        } catch {
            throw BibleOfflineRepositoryError.transport
        }
        guard response.statusCode == 200 else {
            throw BibleOfflineRepositoryError.failed(status: response.statusCode)
        }
        guard let decoded = try? JSONDecoder().decode(BibleSearchEnvelopeDTO.self, from: response.data) else {
            throw BibleOfflineRepositoryError.failed(status: response.statusCode)
        }
        return decoded.data.toDomain()
    }

    /// Mirrors `bible_offline_service.dart`'s `_downloadBook` fetch step
    /// only — the trigger-and-poll retry sequence around a 404/403 is
    /// `BibleOfflineDownloadService`'s job (see that type), not this
    /// repository's, matching Dart's own split between `S3Service`'s dumb
    /// `bibleSnapshotUrl` GET and `BibleOfflineService._downloadBook`'s
    /// orchestration around it.
    func fetchBookSnapshot(language: String, bookNumber: Int) async throws -> [BibleChapter] {
        guard let encodedLanguage = language.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw BibleOfflineRepositoryError.failed(status: 0)
        }
        guard let url = URL(string: "https://\(cdnHost)/hallelujah/system/public/bible-db-snapshot/\(encodedLanguage)/\(bookNumber).json") else {
            throw BibleOfflineRepositoryError.failed(status: 0)
        }

        let data: Data
        let statusCode: Int
        do {
            let (responseData, response) = try await urlSession.data(for: URLRequest(url: url))
            guard let httpResponse = response as? HTTPURLResponse else {
                throw BibleOfflineRepositoryError.transport
            }
            data = responseData
            statusCode = httpResponse.statusCode
        } catch let error as BibleOfflineRepositoryError {
            throw error
        } catch {
            throw BibleOfflineRepositoryError.transport
        }

        // A missing key surfaces as 403 AccessDenied here, not 404 — S3 masks
        // "doesn't exist" as "forbidden" whenever it can't tell the requester
        // which keys exist. See `bible_offline_service.dart`'s identical note
        // and field confirmation (every book of a not-yet-generated language
        // came back 403, never 404).
        guard statusCode != 404, statusCode != 403 else {
            throw BibleOfflineRepositoryError.notFound
        }
        guard statusCode == 200 else {
            throw BibleOfflineRepositoryError.failed(status: statusCode)
        }
        guard let decoded = try? JSONDecoder().decode(BibleSnapshotResponseDTO.self, from: data) else {
            throw BibleOfflineRepositoryError.failed(status: statusCode)
        }
        return decoded.toDomainChapters()
    }

    func triggerSnapshotRegeneration(language: String) async throws -> Bool {
        guard let body = try? JSONEncoder().encode(["languageName": language]) else {
            return false
        }
        do {
            let response = try await client.send(.bibleSnapshotTrigger, body: body)
            logger.debug("Snapshot trigger for \(language) returned \(response.statusCode)")
            return response.statusCode == 202
        } catch {
            logger.warning("Snapshot trigger request failed for \(language): \(error)")
            return false
        }
    }
}
