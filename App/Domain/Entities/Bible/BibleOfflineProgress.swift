import Foundation

/// How far a language download has got, for the UI to render.
/// `bible_offline_service.dart`'s `BibleOfflineProgress`.
struct BibleOfflineProgress: Sendable, Equatable {
    let language: String
    /// Books finished so far — downloaded, already cached, or failed.
    let completed: Int
    /// Books in this run. 0 until the book list has been resolved.
    let total: Int

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(completed) / Double(total), 0), 1)
    }

    var percent: Int { Int((fraction * 100).rounded()) }
}

/// Every Bible language downloading right now, in one snapshot.
/// `bible_offline_service.dart`'s `BibleOfflineStatus`. Languages download
/// independently and concurrently — see `BibleOfflineDownloadService`.
struct BibleOfflineStatus: Sendable, Equatable {
    var active: [BibleOfflineProgress] = []

    static let idle = BibleOfflineStatus()

    var isBusy: Bool { !active.isEmpty }

    func progress(for language: String) -> BibleOfflineProgress? {
        active.first { $0.language == language }
    }

    func isDownloading(_ language: String) -> Bool {
        progress(for: language) != nil
    }
}
