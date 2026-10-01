import Foundation
import UserNotifications

/// A thin, deliberately generic wrapper over
/// `UNUserNotificationCenter`'s pending-request API — the native primitive
/// `flutter_local_notifications` served as for Dart's own download-progress
/// bar (`NotificationService.showDownloadProgress`/`showDownloadResult`,
/// `notification_service.dart`). NOT that logic itself: no image download,
/// progress-bar state, or channel management lives here — T47 (offline
/// downloads) builds that on top of this primitive later. Keeping this
/// minimal now is what lets it be reused for that without dragging
/// download-specific assumptions along.
final class LocalNotificationScheduler: Sendable {
    func post(id: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancel(id: String) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}
