import Foundation

/// Session / diagnostics routes from `lib/utils/end_points.dart` that the
/// session code (`lib/utils/session.dart`) calls but no feature owns.
extension Endpoint {
    /// `logOutApi` (`end_points.dart:~99`) — Dart calls it as
    /// `getData(EndPoints.logOutApi, body: {'delete': reason})`, i.e. the
    /// reason travels as the `delete` QUERY parameter of a GET, not as a body.
    static func logout(reason: String) -> Endpoint {
        .get("/user/logout?delete=\(queryEncoded(reason))")
    }

    /// `auditLogApi` (`'/system/public/audit/logs'`) — `OurSession._trackLogoutEvent`
    /// posts `{action, entity, entityId, metadata}` here, fire-and-forget.
    static let auditLog = Endpoint.post("/system/public/audit/logs")

    /// `clientErrorLogApi` — `AnalyticSession._reportToServer`, development
    /// builds only (`{message, stackTrace}`).
    static let clientErrorLog = Endpoint.post("/client-log/error")

    private static func queryEncoded(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
