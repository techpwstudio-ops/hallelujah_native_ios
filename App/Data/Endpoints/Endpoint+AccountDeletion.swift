import Foundation

extension Endpoint {
    /// `cancelDeleteUserDataApi = '/users/account/cancel/delete'`
    /// (`end_points.dart`), called with `DioApi.getData` — a GET.
    static let cancelAccountDeletion = Endpoint.get("/users/account/cancel/delete")
}
