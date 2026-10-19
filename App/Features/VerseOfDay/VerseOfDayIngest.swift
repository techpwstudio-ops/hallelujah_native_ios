import Foundation

extension Notification.Name {
    /// The current verse of the day, its cached counts, or its hidden flag changed.
    static let verseOfDayDidChange = Notification.Name("Hallelujah.verseOfDayDidChange")
    /// `verseOfDay.comment.added` — `userInfo["comment"]` is a `VerseOfDayComment`.
    static let verseOfDayCommentAdded = Notification.Name("Hallelujah.verseOfDayCommentAdded")
    /// `verseOfDay.comment.like` — `userInfo`: `commentId`, `likes`, `verseOfDayId`.
    static let verseOfDayCommentLikesChanged = Notification.Name("Hallelujah.verseOfDayCommentLikesChanged")
}

/// Everything Flutter does to `getRealm().add<VerseOfDay>(...)` plus
/// `VerseOfDayHistoryVerseOfDayChangedEvent` / `last_verse_of_day_id` whenever a
/// verse of the day arrives: from the Home feed rail (`syncHomePageUiItems*`),
/// a delivered push (`handleFcm`), a clicked push / shared link
/// (`markVerseOfDayClicked`, `openShareable`) and realtime count updates
/// (`_onVerseOfDayUpdated`). The Home card, the reader menu's "Verse of the day"
/// row and the comments sheet all read what this stores.
enum VerseOfDayIngest {
    /// `syncHomePageUiItems*`: the first row of the `verseOfDay` rail becomes the
    /// current verse (`last_verse_of_day_id`) and is cached.
    static func ingestHomeRows(_ rows: [JSONValue]) {
        guard let first = rows.first, let data = try? JSONEncoder().encode(first) else { return }
        ingest(json: data, makeCurrent: true)
    }

    /// A raw server row (a validated share link's `item`), cached without
    /// becoming the Home card's verse.
    static func ingest(item: [String: Any], makeCurrent: Bool) {
        guard JSONSerialization.isValidJSONObject(item),
              let data = try? JSONSerialization.data(withJSONObject: item) else { return }
        ingest(json: data, makeCurrent: makeCurrent)
    }

    /// `handleFcm` for `topic == 'verse_of_day'`: `mark-delivered` returns the
    /// row, which is cached and becomes the current verse.
    static func markDelivered(id: String) {
        Task {
            let repository: any VerseOfDayRepository = DependencyContainer.current.resolve()
            guard let verse = try? await repository.markDelivered(id: id) else { return }
            setCurrent(verse.id)
            await notifyChanged()
        }
    }

    /// `_onVerseOfDayUpdated`: patch the cached verse's like/comment counts.
    static func applyLiveCounts(id: String, likes: Int?, comments: Int?) {
        Task {
            let repository: any VerseOfDayRepository = DependencyContainer.current.resolve()
            guard let cached = await repository.cachedVerse(id: id) else { return }
            await repository.store(cached.updatingCounts(likes: likes, comments: comments))
            await notifyChanged()
        }
    }

    private static func ingest(json: Data, makeCurrent: Bool) {
        guard let dto = try? JSONDecoder().decode(VerseOfDayDTO.self, from: json) else { return }
        let verse = dto.toDomain()
        Task {
            let repository: any VerseOfDayRepository = DependencyContainer.current.resolve()
            await repository.store(verse)
            if makeCurrent { setCurrent(verse.id) }
            await notifyChanged()
        }
    }

    private static func setCurrent(_ id: String) {
        let keyValueStore: any KeyValueStoring = DependencyContainer.current.resolve()
        VerseOfDayLocalStore(keyValueStore: keyValueStore).lastVerseOfDayID = id
    }

    @MainActor
    static func notifyChanged() {
        NotificationCenter.default.post(name: .verseOfDayDidChange, object: nil)
    }
}

extension VerseOfDay {
    func updatingCounts(likes: Int?, comments: Int?) -> VerseOfDay {
        VerseOfDay(
            id: id,
            title: title,
            deliveryStatus: deliveryStatus,
            image: image,
            backgroundImage: backgroundImage,
            verseId: verseId,
            languageName: languageName,
            verseText: verseText,
            bookName: bookName,
            bookNumber: bookNumber,
            chapterNumber: chapterNumber,
            verseNumber: verseNumber,
            likes: likes ?? self.likes,
            shares: shares,
            comments: comments ?? self.comments,
            isLiked: isLiked,
            scheduledAt: scheduledAt,
            sentAt: sentAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension VerseOfDayComment {
    func updatingLikes(_ likes: Int) -> VerseOfDayComment {
        VerseOfDayComment(
            id: id,
            verseOfDayId: verseOfDayId,
            content: content,
            userId: userId,
            userName: userName,
            userImage: userImage,
            userImageVariants: userImageVariants,
            likes: likes,
            isLiked: isLiked,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
