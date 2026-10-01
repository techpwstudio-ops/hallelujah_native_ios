import Foundation

/// `DeepLink.fromJson` (`lib/services/deep_link_service.dart`) — every field
/// optional there too, since not every shareable type populates every field.
struct DeepLink: Decodable, Sendable {
    let code: String?
    let aspectRatio: String?
    let link: String?
    let shareableType: String?
    let title: String?
    let description: String?
    let image: String?
    let imageVariants: String?
}
