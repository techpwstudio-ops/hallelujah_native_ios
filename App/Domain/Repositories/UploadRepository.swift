import Foundation

/// What the backend should treat an upload as — the `uploadType` field of
/// `POST /upload/generate/presigned`.
enum UploadKind: Sendable, Equatable {
    /// `AuthBloc._updateProfile` — `thumbnail-profile`.
    case profilePhoto
    /// `AiService._uploadTypeFromExt`.
    case aiImage
    case aiAudio
    case aiVideo

    var wireValue: String {
        switch self {
        case .profilePhoto: "thumbnail-profile"
        case .aiImage: "ai-image"
        case .aiAudio: "ai-audio"
        case .aiVideo: "ai-video"
        }
    }

    /// `AiService._uploadTypeFromExt` — extension → AI upload type.
    static func aiKind(forExtension ext: String) -> UploadKind? {
        switch ext.lowercased() {
        case "jpg", "jpeg", "png", "gif", "webp", "heic": .aiImage
        case "mp3", "m4a", "wav", "ogg": .aiAudio
        case "mp4", "mov": .aiVideo
        default: nil
        }
    }
}

struct UploadError: Error, Equatable, Sendable {
    let message: String
}

/// Two-step presigned upload shared by profile photos and AI attachments
/// (`AiService.uploadFile` / `AuthBloc._updateProfile`): ask the backend for a
/// presigned S3 URL, then PUT the file straight to S3 (no auth headers).
protocol UploadRepository: Sendable {
    /// Returns the S3 key (`filePath`) to put in the follow-up payload.
    func upload(fileURL: URL, kind: UploadKind, mimeType: String?) async throws -> String
}
