import Foundation
@testable import GHallelujah

extension Song {
    /// A `Song` with only the fields a test names; everything else is nil /
    /// empty. Keeps tests from restating the 45-argument memberwise init.
    static func fixture(
        id: String = "song-1",
        title: String? = "Title",
        type: String? = "music",
        image: String? = "square.png",
        imageVariants: String? = nil,
        rectangleImage: String? = "rect.png",
        rectangleImageVariants: String? = nil,
        duration: Int? = 180,
        primaryArtists: String? = "Artist",
        featuredArtists: String? = nil,
        isFavorited: Bool = false
    ) -> Song {
        Song(
            id: id, title: title, description: nil, type: type,
            image: image, imageVariants: imageVariants,
            rectangleImage: rectangleImage, rectangleImageVariants: rectangleImageVariants,
            audioFile: nil, audioVariants: nil,
            audioUrls: SongAudioURLs(original: nil, low: nil, standard: nil, high: nil),
            duration: duration, language: nil, releaseDate: nil,
            plays: nil, likes: nil, shares: nil, downloads: nil,
            writers: nil, primaryArtists: primaryArtists, featuredArtists: featuredArtists, isrcCode: nil,
            copyrightYear: nil, productionYear: nil, copyrightOwners: nil,
            songStatus: nil, reviewStatus: nil, processingStatus: nil, isScheduled: nil,
            dominantColor: nil, vibrantColor: nil, darkVibrantColor: nil, lightVibrantColor: nil,
            mutedColor: nil, onColor: nil, isDark: nil, gradient: nil,
            createdAt: nil, updatedAt: nil,
            creator: nil, primaryGenre: nil, playlistTitles: [],
            songPrimaryArtists: [], transcripts: nil, songCredits: nil,
            isFavorited: isFavorited
        )
    }
}

extension Playlist {
    static func fixture(
        id: String = "playlist-1",
        title: String = "Playlist",
        type: String? = "music",
        owner: PlaylistOwner = .company
    ) -> Playlist {
        Playlist(
            id: id, title: title, description: nil, image: nil, imageVariants: nil,
            type: type, visibility: nil, language: nil, songsCount: nil, duration: nil, rank: nil,
            owner: owner, createdAt: nil, updatedAt: nil, isSeed: false
        )
    }
}

extension Paginated {
    /// A single, final page holding `items`.
    static func page(_ items: [Item], hasMore: Bool = false, page: Int = 1) -> Paginated<Item> {
        Paginated(items: items, page: page, perPage: nil, total: nil, totalPages: hasMore ? page + 1 : page, hasMore: hasMore)
    }
}

extension SongCredit {
    static func fixture(role: String? = "Producer", name: String? = "Jane", category: String? = nil) -> SongCredit {
        SongCredit(role: role, name: name, category: category)
    }
}
