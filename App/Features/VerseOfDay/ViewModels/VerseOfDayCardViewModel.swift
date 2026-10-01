import Foundation

/// T56 — the Home card's own state. Ports the read side of
/// `VerseOfDayHistoryBloc`'s state (`lib/blocs/verse_of_day_history/bloc.dart`):
/// `verseOfDay`/`isHiddenToday`, sourced from `VerseOfDayLocalStore` (the two
/// `StorageService` keys) plus `VerseOfDayRepository.cachedVerse(id:)` (the
/// `getRealm().find<VerseOfDay>(id)` read) — never a network fetch of its
/// own, matching `VerseOfDayRepository`'s own "no fetchToday()" contract.
@MainActor
@Observable
final class VerseOfDayCardViewModel {
    private let repository: any VerseOfDayRepository
    private let localStore: VerseOfDayLocalStore
    private let logger = AppLogger(category: .content)

    private(set) var verse: VerseOfDay?
    private(set) var isHiddenToday = false
    private(set) var isTogglingLike = false
    /// Prefetched alongside `verse` in `refresh()`, not fetched at share-tap
    /// time — `ShareLink(item:)` needs its `item` ready synchronously
    /// (there's no async gap between tap and the system sheet appearing),
    /// the same constraint `BibleVerseShareView`'s own already-resolved
    /// `shareURL` satisfies for its screen.
    private(set) var shareURL: URL?

    init(container: DependencyContainer = .current) {
        repository = container.resolve()
        localStore = VerseOfDayLocalStore(keyValueStore: container.resolve())
    }

    var isVisible: Bool { verse != nil && !isHiddenToday }

    func refresh() async {
        isHiddenToday = localStore.isHiddenToday
        guard let id = localStore.lastVerseOfDayID else {
            verse = nil
            shareURL = nil
            return
        }
        verse = await repository.cachedVerse(id: id)
        shareURL = try? await repository.shareURL(id: id)
    }

    /// `showVerseOfDayOptionsSheet`'s "Hide for Today" row.
    func hideForToday() {
        localStore.hideForToday()
        isHiddenToday = true
    }

    func toggleLike() async {
        guard let verse, !isTogglingLike else { return }
        isTogglingLike = true
        defer { isTogglingLike = false }
        do {
            self.verse = try await repository.toggleLike(id: verse.id)
        } catch {
            logger.warning("verse of day like toggle failed: \(error)")
        }
    }
}
