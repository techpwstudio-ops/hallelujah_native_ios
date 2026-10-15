import PhotosUI
import SwiftUI
import UIKit

/// `_pickFile` + `AiService.uploadFile` shared by the AI tab's empty state and
/// the conversation view: a picked photo becomes a JPEG temp file plus a
/// "pending" strip entry, then goes through the presigned-upload flow.
enum AIAttachmentStaging {
    struct Staged {
        let pending: AIPendingAttachment
        let fileURL: URL
    }

    static let mimeType = "image/jpeg"

    static func stage(_ item: PhotosPickerItem) async -> Staged? {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let jpeg = image.jpegData(compressionQuality: 0.9) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
        do { try jpeg.write(to: url, options: .atomic) } catch { return nil }
        let pending = AIPendingAttachment(
            id: UUID(),
            fileName: url.lastPathComponent,
            thumbnail: image,
            isUploading: true,
            uploadedKey: nil,
            mimeType: mimeType
        )
        return Staged(pending: pending, fileURL: url)
    }

    /// The S3 key on success, nil on failure.
    static func upload(_ staged: Staged, using repository: any UploadRepository) async -> String? {
        try? await repository.upload(fileURL: staged.fileURL, kind: .aiImage, mimeType: mimeType)
    }

    /// The fully uploaded entries as send-payload attachments (`_send`/`_onSendTap`).
    static func payloads(from attachments: [AIPendingAttachment]) -> [AIAttachmentPayload] {
        attachments.compactMap { attachment in
            attachment.uploadedKey.map { AIAttachmentPayload(key: $0, mimeType: attachment.mimeType) }
        }
    }
}
