import Foundation

/// `UploadRepository` over the app's `HTTPClient` (presign) and a bare
/// `URLSession` (the S3 PUT — Dio's separate uploader instance exists for the
/// same reason: our auth/secure headers must not reach the presigned URL).
struct RemoteUploadRepository: UploadRepository {
    private struct PresignRequest: Encodable {
        let uploadType: String
        let `extension`: String
    }

    private struct PresignResponse: Decodable {
        let uploadUrl: String
        let filePath: String
    }

    private struct ErrorBody: Decodable { let message: String? }

    let client: HTTPClient
    var session: URLSession = .shared

    func upload(fileURL: URL, kind: UploadKind, mimeType: String?) async throws -> String {
        let ext = fileURL.pathExtension.lowercased()
        let body = try JSONEncoder().encode(PresignRequest(uploadType: kind.wireValue, extension: ext))
        let presign = try await client.send(.presignedUpload, body: body)
        guard presign.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: presign.data))?.message
            throw UploadError(message: message ?? String(localized: "Failed to get upload URL"))
        }
        let decoded = try JSONDecoder().decode(PresignResponse.self, from: presign.data)
        guard let url = URL(string: decoded.uploadUrl) else {
            throw UploadError(message: String(localized: "Failed to get upload URL"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(mimeType ?? "application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.upload(for: request, fromFile: fileURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw UploadError(message: String(localized: "File upload to S3 failed (\(code))"))
        }
        return decoded.filePath
    }
}
