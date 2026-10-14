import Foundation

extension Endpoint {
    /// `generatePresignedUrlApi` (`end_points.dart:308`) — `POST
    /// /upload/generate/presigned` with `{uploadType, extension}`; replies
    /// `{uploadUrl, filePath}`.
    static let presignedUpload = Endpoint.post("/upload/generate/presigned")
}
