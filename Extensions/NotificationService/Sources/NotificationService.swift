import UserNotifications

/// Downloads and attaches the `fcm_options.image` URL the backend sets on
/// every push with an image (see gs_nh_backend firebase.service.js) so it
/// renders in the system notification. iOS only invokes this extension when
/// the payload's `aps.mutable-content` flag is 1 — the backend already sets
/// that whenever an image is present, but without this extension target
/// there was nothing installed to receive the hand-off and do the download.
class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        guard let bestAttemptContent = bestAttemptContent else {
            contentHandler(request.content)
            return
        }

        guard
            let fcmOptions = request.content.userInfo["fcm_options"] as? [String: Any],
            let imageUrlString = fcmOptions["image"] as? String,
            let imageUrl = URL(string: imageUrlString)
        else {
            contentHandler(bestAttemptContent)
            return
        }

        downloadImage(from: imageUrl) { attachment in
            if let attachment = attachment {
                bestAttemptContent.attachments = [attachment]
            }
            contentHandler(bestAttemptContent)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // System gives ~30s total; if the download hasn't finished, ship
        // whatever we have rather than let the notification silently drop.
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    private func downloadImage(from url: URL, completion: @escaping (UNNotificationAttachment?) -> Void) {
        let task = URLSession.shared.downloadTask(with: url) { tempFileUrl, _, error in
            guard let tempFileUrl = tempFileUrl, error == nil else {
                completion(nil)
                return
            }

            let fileManager = FileManager.default
            let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
            let destinationUrl = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)

            do {
                try fileManager.moveItem(at: tempFileUrl, to: destinationUrl)
                let attachment = try UNNotificationAttachment(
                    identifier: destinationUrl.lastPathComponent,
                    url: destinationUrl,
                    options: nil
                )
                completion(attachment)
            } catch {
                completion(nil)
            }
        }
        task.resume()
    }
}
