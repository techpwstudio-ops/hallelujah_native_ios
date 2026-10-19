import Foundation
import Observation

/// T46 — the offline-download engine: a background `URLSession`, up to 3
/// concurrent transfers, and the catalog of what's been downloaded. Mirrors
/// `AudioEngine`'s own shape (`@Observable @MainActor final class` wrapping
/// a system API) rather than `AudioEngine` itself — this owns its own
/// session, not the player's.
///
/// Ports `DownloaderBloc`/`MyDownloadTask` (`lib/blocs/downloader/bloc.dart`,
/// `lib/models/my_download_task.dart`), which drove Dart's `flutter_downloader`
/// plugin. There's no native equivalent to port *to* here beyond `URLSession`
/// itself, so this is closer to a from-scratch design than most T4x ports —
/// grounded against Dart's behavior where it matters (fire-and-forget
/// completion ping, reconciliation on load) but not its implementation.
///
/// Two deliberate departures from Dart, both intentional per the task spec:
/// - `retry(songID:)` actually re-enqueues. Dart's `retryDownload` calls
///   `FlutterDownloader.retry(taskId:)` against a taskId `MyDownloadTask`
///   never actually persists across the enum mapping it goes through
///   (`_mapStringToDownloadTaskStatus`/`updateTask` never round-trips a real
///   plugin taskId back in), so it silently no-ops in practice. This does
///   the real thing: reset to `.queued` and let normal promotion restart it.
/// - The Wi-Fi-only toggle IS honoured: the `download_wifi_only` flag Settings
///   writes (`SettingsView`) is read at the moment each transfer's request is
///   built and mapped to `allowsCellularAccess = false`, the native analog of
///   `FlutterDownloader.enqueue(allowCellular:)`.
///
/// ## Song snapshots, not a cache
/// There is no local `Song` cache anywhere in this app yet (`Database.swift`'s
/// own doc comment: GRDB has zero tables registered). `DownloadTask` copes by
/// denormalizing the handful of `Song` fields a downloads list actually
/// renders (`songTitle`, `songArtworkPath`, …) directly onto itself at
/// `enqueue` time, the same snapshot approach `MyDownloadTask` uses. That
/// covers *display*, but not *resolving a fresh source URL* — `resume`/
/// `retry`/queue-promotion all need a full `Song` to call
/// `AudioSourceResolver.resolve(song:targetQuality:)` again (a presigned URL
/// can expire, or tier-2 proxying needs `audioFile`/`audioVariants`, neither
/// of which `DownloadTask` stores). This engine keeps a small in-memory-only
/// `songs` cache, populated at `enqueue`, for exactly that. A `.paused` or
/// `.queued` task that outlives a relaunch has no `Song` left to resolve a
/// fresh source from — `resume`/`retry`/queue-promotion below all detect
/// that case and surface it as `.failed` (safely retryable, never silently
/// stuck) rather than pretend they can restart it.
@MainActor
@Observable
final class DownloadEngine {
    private(set) var tasks: [String: DownloadTask] = [:]

    /// Sum of `bytesWritten` across every task still "on disk" in some form
    /// — queued/downloading/paused ones count their partial bytes, completed
    /// ones their full size. `.failed` is excluded: a failed transfer's
    /// partial bytes were already deleted (see `handleDownloadFailed`), so
    /// it has nothing left occupying storage to count.
    var totalBytesUsed: Int64 {
        tasks.values.reduce(into: 0) { total, task in
            switch task.state {
            case .queued, .downloading, .paused, .completed:
                total += task.bytesWritten
            case .failed:
                break
            }
        }
    }

    private let tokenProvider: any AuthTokenProviding
    private let catalogStore: DownloadCatalogStore
    private let client: HTTPClient
    private let sourceResolver: AudioSourceResolver
    private let urlSession: URLSession
    private let sessionDelegate: DownloadSessionDelegate
    private let logger = AppLogger(category: .playback)

    /// Session-scoped only, never persisted — see this file's top doc
    /// comment. Populated at `enqueue`, consulted by `resume`/`retry`/queue
    /// promotion, cleared once a task is `.completed`/deleted/cancelled.
    private var songs: [String: Song] = [:]
    /// Live OS task handles for every in-flight download, keyed by songID
    /// (one download per song) — lets `pause`/`cancel` act on the real task
    /// directly instead of re-querying `getAllTasks` on every call.
    private var activeDownloadTasks: [String: URLSessionDownloadTask] = [:]
    /// From `URLSessionDownloadTask.cancel(byProducingResumeData:)` — lets
    /// `resume(songID:)` continue a paused transfer instead of restarting it
    /// from byte zero. Session-scoped only, same reasoning as `songs`.
    private var resumeData: [String: Data] = [:]
    /// Throttle state for requirement #8 — see `persistThrottled`.
    private var lastPersistedProgressAt: [String: Date] = [:]

    private static let maxConcurrentDownloads = 3
    private static let backgroundSessionIdentifierSuffix = ".downloads"
    /// How often a bare progress tick (`didWriteData`) is allowed to hit
    /// disk for a given song. State transitions (queued->downloading,
    /// ->completed, ->failed, ->paused) always persist immediately
    /// regardless of this — this only throttles the high-frequency,
    /// low-stakes byte-count ticks in between.
    private static let progressPersistInterval: TimeInterval = 1

    init(
        proxyBaseURL: URL,
        tokenProvider: any AuthTokenProviding,
        catalogStore: DownloadCatalogStore,
        client: HTTPClient
    ) {
        self.tokenProvider = tokenProvider
        self.catalogStore = catalogStore
        self.client = client
        sourceResolver = AudioSourceResolver(proxyBaseURL: proxyBaseURL)

        let loadedTasks = catalogStore.load()
        tasks = Dictionary(loadedTasks.map { ($0.songID, $0) }, uniquingKeysWith: { _, latest in latest })

        // Same fallback `KeychainTokenStore`/`AppLogger` already use — there's
        // no bundle-identifier accessor on `AppConfiguration` to read a
        // static xcconfig value from instead, and the runtime bundle id
        // already reflects any per-environment suffix (`.dev`/`.staging`)
        // that a static `APP_BUNDLE_ID_BASE` wouldn't.
        let backgroundSessionIdentifier = (Bundle.main.bundleIdentifier ?? "com.hallelujah.user")
            + Self.backgroundSessionIdentifierSuffix

        let delegate = DownloadSessionDelegate(downloadsDirectory: catalogStore.downloadsDirectory)
        sessionDelegate = delegate

        let configuration = URLSessionConfiguration.background(withIdentifier: backgroundSessionIdentifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        urlSession = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)

        // Set once, synchronously, before this initializer returns — no
        // background delegate callback can possibly fire before that, so
        // `engine` needs no lock of its own despite being read from the
        // delegate queue later (see `DownloadSessionDelegate`'s own note).
        delegate.engine = self

        Task { [weak self] in
            await self?.reconcileWithExistingTasks()
        }
    }

    // MARK: - Public control surface

    func enqueue(song: Song, quality: AudioQuality) async {
        // Matches Dart's own `enqueue` no-op-if-present behavior
        // (`DownloaderBloc`'s `_onEnqueueDownload` checks `state.tasks[songId]`
        // first) — one download per song, callers that want a different
        // quality re-download by cancelling first.
        guard tasks[song.id] == nil else { return }

        songs[song.id] = song
        let now = Date()
        tasks[song.id] = DownloadTask(
            songID: song.id,
            state: .queued,
            quality: quality,
            bytesWritten: 0,
            totalBytes: nil,
            localFileName: nil,
            createdAt: now,
            updatedAt: now,
            urlSessionTaskIdentifier: nil,
            songTitle: song.title ?? "Untitled",
            songArtworkPath: song.displayImage,
            songArtworkVariants: song.displayImageVariants,
            songGenreName: song.primaryGenre?.name,
            songDurationSeconds: song.duration,
            songType: song.type,
            songPrimaryArtists: song.primaryArtists,
            songFeaturedArtists: song.featuredArtists
        )
        persist()
        await startNextQueuedIfNeeded()
    }

    func pause(songID: String) {
        guard var task = tasks[songID], task.state == .downloading else { return }
        task.state = .paused
        task.updatedAt = Date()
        tasks[songID] = task
        persist()

        // A `.paused` task no longer counts toward `downloadingCount()` (see
        // that method), so pausing genuinely frees a concurrency slot — a
        // queued task waiting behind the cap should be promoted into it,
        // same as every other slot-freeing path below (`cancel`,
        // `handleDownloadCompleted`, `handleDownloadFailed`).
        Task { await startNextQueuedIfNeeded() }

        guard let downloadTask = activeDownloadTasks[songID] else { return }
        activeDownloadTasks[songID] = nil
        sessionDelegate.forget(taskIdentifier: downloadTask.taskIdentifier)
        // The resume-data completion handler fires on an arbitrary queue,
        // not the caller's — hop back before touching `resumeData`.
        downloadTask.cancel { [weak self] data in
            guard let data else { return }
            Task { @MainActor in
                self?.resumeData[songID] = data
            }
        }
    }

    func resume(songID: String) {
        guard var task = tasks[songID], task.state == .paused else { return }

        if let data = resumeData[songID], let fileName = task.localFileName {
            resumeData[songID] = nil
            let downloadTask = urlSession.downloadTask(withResumeData: data)
            startTracking(downloadTask, songID: songID, destinationFileName: fileName)
            task.state = .downloading
            task.urlSessionTaskIdentifier = downloadTask.taskIdentifier
            task.updatedAt = Date()
            tasks[songID] = task
            persist()
            downloadTask.resume()
            return
        }

        // No resume data on hand — most likely this process was relaunched
        // since the pause, since resume data (like `songs`, below) only
        // lives in memory. Re-queue so normal promotion restarts it from
        // scratch once a slot frees up, but only if this process still has
        // the `Song` needed to resolve a fresh source URL; otherwise this is
        // a no-op the caller has to work around by re-triggering `enqueue`
        // with a freshly-fetched `Song` (see this file's top doc comment).
        // Otherwise re-fetch the song (`DownloaderBloc` re-reads it from the
        // API when Realm lacks it) so the transfer can still restart.
        task.state = .queued
        task.updatedAt = Date()
        tasks[songID] = task
        persist()
        Task {
            await restoreSongIfNeeded(songID: songID)
            await startNextQueuedIfNeeded()
        }
    }

    func cancel(songID: String) {
        guard let task = tasks[songID] else { return }

        if let downloadTask = activeDownloadTasks[songID] {
            activeDownloadTasks[songID] = nil
            sessionDelegate.forget(taskIdentifier: downloadTask.taskIdentifier)
            downloadTask.cancel()
        }
        resumeData[songID] = nil
        songs[songID] = nil
        removeLocalFile(named: task.localFileName)
        tasks[songID] = nil
        persist()
        Task { await startNextQueuedIfNeeded() }
    }

    /// A REAL re-enqueue, unlike Dart's dead `retryDownload` (see top doc
    /// comment) — resets to `.queued` and lets normal promotion restart it.
    func retry(songID: String) async {
        guard tasks[songID]?.state == .failed else { return }
        await restoreSongIfNeeded(songID: songID)
        guard songs[songID] != nil else {
            logger.warning("retry requested for song \(songID) and the song could not be re-fetched; ignoring")
            return
        }
        guard var task = tasks[songID], task.state == .failed else { return }
        task.state = .queued
        task.bytesWritten = 0
        task.totalBytes = nil
        task.urlSessionTaskIdentifier = nil
        task.updatedAt = Date()
        tasks[songID] = task
        persist()
        await startNextQueuedIfNeeded()
    }

    func deleteDownload(songID: String) {
        guard let task = tasks[songID], task.state == .completed else { return }
        removeLocalFile(named: task.localFileName)
        tasks[songID] = nil
        songs[songID] = nil
        persist()
        CarIntegrationNotifier.downloadsChanged()
    }

    /// Called by `AppComposition`'s sign-out closure and the "delete all
    /// downloads" UI action alike — tears down every in-flight transfer too,
    /// not just completed files.
    func deleteAll() {
        for (songID, downloadTask) in activeDownloadTasks {
            sessionDelegate.forget(taskIdentifier: downloadTask.taskIdentifier)
            downloadTask.cancel()
            resumeData[songID] = nil
        }
        activeDownloadTasks.removeAll()
        resumeData.removeAll()
        songs.removeAll()
        tasks.removeAll()

        let fileManager = FileManager.default
        if let contents = try? fileManager.contentsOfDirectory(
            at: catalogStore.downloadsDirectory,
            includingPropertiesForKeys: nil
        ) {
            for url in contents {
                try? fileManager.removeItem(at: url)
            }
        }
        persist()
        CarIntegrationNotifier.downloadsChanged()
    }

    func isDownloaded(songID: String) -> Bool {
        localFileURL(for: songID) != nil
    }

    /// `nil` unless `.completed` AND the file still genuinely exists on
    /// disk — catalog state alone isn't trusted, since an OS storage purge
    /// or a manual deletion can silently invalidate a `.completed` entry
    /// without this engine ever hearing about it. Used by T47 (offline
    /// playback source selection and offline library dimming).
    func localFileURL(for songID: String) -> URL? {
        guard let task = tasks[songID], task.state == .completed, let fileName = task.localFileName else {
            return nil
        }
        let url = catalogStore.downloadsDirectory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// `AppDelegate`'s `application(_:handleEventsForBackgroundURLSession:completionHandler:)`
    /// hands this straight through. Only the identifier this engine's own
    /// session was created with matters — a mismatched identifier means the
    /// relaunch was for some other background session, so the handler is
    /// dropped rather than fired early against the wrong session's events.
    func handleEventsForBackgroundURLSession(identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == urlSession.configuration.identifier else { return }
        sessionDelegate.backgroundCompletionHandler = completionHandler
    }

    // MARK: - Queue promotion

    /// Requirement #5: at most `maxConcurrentDownloads` simultaneous
    /// `.downloading` tasks. Called after every completion/failure/
    /// cancellation/pause and after every fresh `enqueue`/`retry`/`resume`-
    /// via-requeue, so a freed slot (or a newly queued task) is always
    /// picked up promptly rather than only on the next unrelated call.
    private func startNextQueuedIfNeeded() async {
        while downloadingCount() < Self.maxConcurrentDownloads {
            guard let next = tasks.values
                .filter({ $0.state == .queued })
                .sorted(by: { $0.createdAt < $1.createdAt })
                .first
            else { return }

            guard let song = songs[next.songID] else {
                // No cached `Song` to resolve a source from (relaunch since
                // this was queued, and nothing has re-supplied it) — fail it
                // so it's visibly retryable rather than stuck `.queued`
                // forever, matching requirement #6's relaunch reconciliation
                // for the exact same underlying gap.
                var failed = next
                failed.state = .failed
                failed.updatedAt = Date()
                tasks[next.songID] = failed
                persist()
                continue
            }

            await startDownloadTask(songID: next.songID, song: song, quality: next.quality)
        }
    }

    private func downloadingCount() -> Int {
        tasks.values.filter { $0.state == .downloading }.count
    }

    /// Requirement #4: resolves the source URL — and attaches the auth
    /// header only if that resolution says to — at the moment the real
    /// `URLSessionDownloadTask` is created, not any earlier.
    private func startDownloadTask(songID: String, song: Song, quality: AudioQuality) async {
        guard let resolved = sourceResolver.resolve(song: song, targetQuality: quality) else {
            logger.warning("no playable source for song \(songID); marking download failed")
            if var task = tasks[songID] {
                task.state = .failed
                task.updatedAt = Date()
                tasks[songID] = task
                persist()
            }
            return
        }

        var request = URLRequest(url: resolved.url)
        request.allowsCellularAccess = Self.allowsCellularDownloads()
        if resolved.requiresAuthHeader {
            // Tier-2 proxy only (tier-1 presigned CloudFront never needs
            // this). May go stale by the time the OS actually runs the
            // background task — acceptable per this task's own contract;
            // the user retries with a fresh token if that happens.
            let token = await tokenProvider.currentAccessToken() ?? ""
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let destinationFileName = "\(songID).\(Self.fileExtension(for: resolved))"
        let downloadTask = urlSession.downloadTask(with: request)
        startTracking(downloadTask, songID: songID, destinationFileName: destinationFileName)

        // `await tokenProvider.currentAccessToken()` above is a suspension
        // point another call (`cancel(songID:)`) could race across — if the
        // task entry vanished out from under us while we were suspended,
        // tear the OS task we just created back down rather than leaving an
        // orphaned transfer running for a song nothing tracks anymore.
        guard var task = tasks[songID] else {
            sessionDelegate.forget(taskIdentifier: downloadTask.taskIdentifier)
            activeDownloadTasks[songID] = nil
            downloadTask.cancel()
            return
        }

        task.state = .downloading
        task.quality = resolved.quality
        task.localFileName = destinationFileName
        task.urlSessionTaskIdentifier = downloadTask.taskIdentifier
        task.updatedAt = Date()
        tasks[songID] = task
        persist()

        downloadTask.resume()
    }

    /// After a relaunch the in-memory `songs` cache is empty, but resolving a
    /// fresh source URL needs the full `Song`. Re-fetch it (`saveSong` in
    /// `DownloaderBloc._load`) so a failed or paused download stays retryable.
    private func restoreSongIfNeeded(songID: String) async {
        guard songs[songID] == nil,
              let repository = DependencyContainer.current.resolveIfRegistered((any SongRepository).self),
              let song = try? await repository.fetchSong(id: songID)
        else { return }
        songs[songID] = song
    }

    /// `!(StorageService.getBoolean("download_wifi_only") == true)`.
    nonisolated static let wifiOnlyKey = "download_wifi_only"

    private static func allowsCellularDownloads() -> Bool {
        let store: any KeyValueStoring = DependencyContainer.current.resolve()
        return !store.bool(forKey: wifiOnlyKey)
    }

    private func startTracking(_ downloadTask: URLSessionDownloadTask, songID: String, destinationFileName: String) {
        activeDownloadTasks[songID] = downloadTask
        sessionDelegate.register(taskIdentifier: downloadTask.taskIdentifier, songID: songID, destinationFileName: destinationFileName)
    }

    // MARK: - Delegate callback handlers (hopped to @MainActor — see `DownloadSessionDelegate`)

    fileprivate func handleDownloadCompleted(songID: String, taskIdentifier: Int, fileName: String) async {
        guard var task = tasks[songID], task.urlSessionTaskIdentifier == taskIdentifier else { return }
        activeDownloadTasks[songID] = nil
        task.state = .completed
        task.localFileName = fileName
        if let totalBytes = task.totalBytes {
            task.bytesWritten = totalBytes
        }
        task.urlSessionTaskIdentifier = nil
        task.updatedAt = Date()
        tasks[songID] = task
        persist()
        songs[songID] = nil

        notifyServerOfCompletedDownload(songID: songID)
        CarIntegrationNotifier.downloadsChanged()
        await startNextQueuedIfNeeded()
    }

    fileprivate func handleDownloadFailed(songID: String, taskIdentifier: Int) async {
        guard var task = tasks[songID], task.urlSessionTaskIdentifier == taskIdentifier else { return }
        activeDownloadTasks[songID] = nil
        removeLocalFile(named: task.localFileName)
        task.state = .failed
        task.bytesWritten = 0
        task.totalBytes = nil
        task.localFileName = nil
        task.urlSessionTaskIdentifier = nil
        task.updatedAt = Date()
        tasks[songID] = task
        persist()
        await startNextQueuedIfNeeded()
    }

    fileprivate func handleProgress(songID: String, taskIdentifier: Int, bytesWritten: Int64, totalBytes: Int64?) {
        guard var task = tasks[songID], task.state == .downloading, task.urlSessionTaskIdentifier == taskIdentifier else { return }
        task.bytesWritten = bytesWritten
        if let totalBytes, totalBytes > 0 {
            task.totalBytes = totalBytes
        }
        task.updatedAt = Date()
        tasks[songID] = task
        persistThrottled(songID: songID)
    }

    fileprivate func handleBackgroundSessionEventsFinished(_ completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    // MARK: - Relaunch reconciliation (requirement #6)

    private func reconcileWithExistingTasks() async {
        let existingTasks = await withCheckedContinuation { (continuation: CheckedContinuation<[URLSessionTask], Never>) in
            urlSession.getAllTasks { continuation.resume(returning: $0) }
        }
        let existingByIdentifier = Dictionary(uniqueKeysWithValues: existingTasks.map { ($0.taskIdentifier, $0) })

        var didChange = false
        for task in Array(tasks.values) {
            guard task.state == .downloading || task.state == .queued else { continue }

            if let identifier = task.urlSessionTaskIdentifier,
               let osTask = existingByIdentifier[identifier] as? URLSessionDownloadTask,
               let fileName = task.localFileName {
                activeDownloadTasks[task.songID] = osTask
                sessionDelegate.register(taskIdentifier: identifier, songID: task.songID, destinationFileName: fileName)
                continue
            }

            // Claims `.downloading`/`.queued` but no matching real OS task
            // survived the relaunch (or a `.queued` entry, which never had
            // one to begin with) — mark `.failed` so it's safely retryable
            // rather than stuck forever. `retry()` will in turn need a fresh
            // `Song` this process doesn't have yet, same gap noted throughout.
            var failedTask = task
            failedTask.state = .failed
            failedTask.bytesWritten = 0
            failedTask.totalBytes = nil
            failedTask.urlSessionTaskIdentifier = nil
            failedTask.updatedAt = Date()
            tasks[task.songID] = failedTask
            didChange = true
        }

        if didChange {
            persist()
        }
        await startNextQueuedIfNeeded()
    }

    // MARK: - Persistence

    private func persist() {
        do {
            try catalogStore.save(Array(tasks.values))
        } catch {
            logger.warning("failed to persist download catalog: \(error)")
        }
    }

    /// Requirement #8: `didWriteData` can fire many times a second per
    /// transfer, and with 3 concurrent transfers that's a lot of disk
    /// writes for a number the UI mostly just needs to look smooth — the
    /// in-memory `tasks` dict (and therefore the UI, via `@Observable`)
    /// still updates on every single callback; only the disk write is
    /// throttled, to roughly once/second per song. State-transition writes
    /// (`persist()`, called directly elsewhere) are never throttled.
    private func persistThrottled(songID: String) {
        let now = Date()
        if let last = lastPersistedProgressAt[songID], now.timeIntervalSince(last) < Self.progressPersistInterval {
            return
        }
        lastPersistedProgressAt[songID] = now
        persist()
    }

    // MARK: - Analytics (requirement #7)

    /// Fire-and-forget, matching Dart's own posture (`DioApi.instance
    /// .getData(EndPoints.songDownloaded(id))`, unawaited, in
    /// `DownloaderBloc`'s completion handling) — not awaited, not retried,
    /// and a failure here never reverts or fails the download itself.
    private func notifyServerOfCompletedDownload(songID: String) {
        Task { [client] in
            _ = try? await client.send(.songDownloadTracked(songId: songID))
        }
    }

    // MARK: - Helpers

    private func removeLocalFile(named fileName: String?) {
        guard let fileName else { return }
        try? FileManager.default.removeItem(at: catalogStore.downloadsDirectory.appendingPathComponent(fileName))
    }

    /// Mirrors Dart's own `getExtensionFromVariant` (`s3_service.dart:189-197`):
    /// an optimized variant's URL/key always ends `.m4a`; an un-optimized
    /// original keeps whatever extension its own path has. Falling back to
    /// `"m4a"` also covers tier-2 proxy URLs, whose `/proxy?path=` query
    /// string leaves the URL's own `pathExtension` empty.
    private static func fileExtension(for resolved: AudioSourceResolver.ResolvedSource) -> String {
        let ext = resolved.url.pathExtension
        return ext.isEmpty ? "m4a" : ext
    }
}

// MARK: - DownloadSessionDelegate

/// The actual `URLSessionDownloadDelegate`/`URLSessionTaskDelegate`
/// conformer — deliberately NOT `DownloadEngine` itself (requirement #2):
/// these callbacks fire on an arbitrary background queue, never the main
/// thread, so `DownloadEngine`'s `@MainActor`-isolated state can't be
/// touched from inside them directly. This holds a `weak` back-reference
/// instead and hops to `@MainActor` for every callback before touching it.
///
/// `pending` tracks, per OS task identifier, which song/destination
/// filename a task belongs to — needed synchronously inside
/// `didFinishDownloadingTo` (requirement #3, see below) before any
/// `@MainActor` hop is possible, so it's plain `NSLock`-protected state
/// rather than something that lives on `DownloadEngine`.
private final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private struct PendingDownload {
        let songID: String
        let destinationFileName: String
    }

    /// Set exactly once, synchronously, by `DownloadEngine.init` — right
    /// after both objects exist and strictly before the session this
    /// delegate is attached to can have fired a single callback. Never
    /// reassigned after that, so reading it from the delegate queue without
    /// the lock below is safe in practice; only `pending` needs one.
    weak var engine: DownloadEngine?
    var backgroundCompletionHandler: (() -> Void)?

    private let downloadsDirectory: URL
    private let lock = NSLock()
    private var pending: [Int: PendingDownload] = [:]

    init(downloadsDirectory: URL) {
        self.downloadsDirectory = downloadsDirectory
    }

    func register(taskIdentifier: Int, songID: String, destinationFileName: String) {
        lock.lock()
        pending[taskIdentifier] = PendingDownload(songID: songID, destinationFileName: destinationFileName)
        lock.unlock()
    }

    func forget(taskIdentifier: Int) {
        lock.lock()
        pending[taskIdentifier] = nil
        lock.unlock()
    }

    private func pendingDownload(for taskIdentifier: Int) -> PendingDownload? {
        lock.lock()
        defer { lock.unlock() }
        return pending[taskIdentifier]
    }

    // MARK: URLSessionDownloadDelegate

    /// Requirement #3 — CRITICAL: the OS deletes `location` the instant this
    /// method returns, so the move to a durable destination must happen
    /// synchronously, right here, before returning — not inside a dispatched
    /// `Task`. Only once that move has actually succeeded does this hop to
    /// `@MainActor` to update `tasks` and persist.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let taskIdentifier = downloadTask.taskIdentifier
        guard let pendingDownload = pendingDownload(for: taskIdentifier) else { return }

        let destination = downloadsDirectory.appendingPathComponent(pendingDownload.destinationFileName)
        let fileManager = FileManager.default
        do {
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: location, to: destination)
        } catch {
            forget(taskIdentifier: taskIdentifier)
            Task { @MainActor [weak engine] in
                await engine?.handleDownloadFailed(songID: pendingDownload.songID, taskIdentifier: taskIdentifier)
            }
            return
        }

        forget(taskIdentifier: taskIdentifier)
        Task { @MainActor [weak engine] in
            await engine?.handleDownloadCompleted(
                songID: pendingDownload.songID,
                taskIdentifier: taskIdentifier,
                fileName: pendingDownload.destinationFileName
            )
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let taskIdentifier = downloadTask.taskIdentifier
        guard let pendingDownload = pendingDownload(for: taskIdentifier) else { return }
        let totalBytes = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        Task { @MainActor [weak engine] in
            engine?.handleProgress(
                songID: pendingDownload.songID,
                taskIdentifier: taskIdentifier,
                bytesWritten: totalBytesWritten,
                totalBytes: totalBytes
            )
        }
    }

    // MARK: URLSessionTaskDelegate

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let taskIdentifier = task.taskIdentifier
        guard let pendingDownload = pendingDownload(for: taskIdentifier) else { return }

        // A deliberate `pause(songID:)` cancels the OS task too (after
        // already calling `forget` and swapping it for resume data), so by
        // the time that cancellation error actually arrives here `pending`
        // no longer has an entry for it and this whole branch is skipped —
        // this only ever reaches `handleDownloadFailed` for a genuine
        // network/server failure or a user-initiated `cancel(songID:)` that
        // raced ahead of `forget` (harmless: `handleDownloadFailed` itself
        // no-ops once the task is no longer in `tasks` at all).
        if let urlError = error as? URLError, urlError.code == .cancelled {
            forget(taskIdentifier: taskIdentifier)
            return
        }

        forget(taskIdentifier: taskIdentifier)
        Task { @MainActor [weak engine] in
            await engine?.handleDownloadFailed(songID: pendingDownload.songID, taskIdentifier: taskIdentifier)
        }
    }

    // MARK: URLSessionDelegate

    /// `AppDelegate`'s saved completion handler (via `handleEventsForBackgroundURLSession`)
    /// finally gets called here, once every queued delegate callback for this
    /// background session has been delivered — the system's own signal that
    /// it's safe to tell it this app is done processing them.
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let completionHandler = backgroundCompletionHandler else { return }
        backgroundCompletionHandler = nil
        Task { @MainActor [weak engine] in
            engine?.handleBackgroundSessionEventsFinished(completionHandler)
        }
    }
}

// MARK: - Endpoint

extension Endpoint {
    /// `markAsSongDownloaded` (`dashboard.routes.js:215`, mounted at `/api`
    /// via `app.use("/api", userDashboardRoutes)` in `app.js`) —
    /// `GET /api/song/:id/download`, the same route Dart fires fire-and-forget
    /// on download completion (`EndPoints.songDownloaded`,
    /// `lib/utils/end_points.dart:235`). Analytics only — plain GET, no
    /// body, response ignored, never retried.
    ///
    /// Added here rather than in `Endpoint.swift`'s own extension only
    /// because this task is scoped to `DownloadEngine.swift` alone (T46) —
    /// Swift extensions compose across files with no functional difference,
    /// so this can be folded into `Endpoint.swift` directly next time that
    /// file is touched for something else.
    static func songDownloadTracked(songId: String) -> Endpoint {
        .get("/song/\(songId)/download")
    }
}
