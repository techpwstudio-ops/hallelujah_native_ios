import Foundation

extension Endpoint {
    // MARK: Saving to the library — `end_points.dart`'s
    // `getLibraryItemIdsApi` / `toggleLibraryItemApi`.

    static let libraryItemIDs = Endpoint.get("/library/items/ids")

    static func toggleLibraryItem(type: LibraryItemType, id: String) -> Endpoint {
        .post("/library/items/\(type.apiName)/\(id)/toggle")
    }
}

extension Endpoint {
    /// `getCreatorsApi` (`end_points.dart:168`) — `GET /creators?page=N`, the
    /// full creator catalogue `CreatorGridPage` paginates through.
    static func allCreators(page: Int) -> Endpoint {
        .get("/creators?page=\(page)")
    }
}
