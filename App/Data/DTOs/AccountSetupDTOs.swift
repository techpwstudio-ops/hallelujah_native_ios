import Foundation

/// `initData` as `AccountSetupPageState._submitDetails` (`account_setup_page.dart`)
/// actually posts it: only the four fields `_DetailsStep` collects, plus the
/// `name` it derives from two of them right before the request goes out
/// (`initData['name'] = "${initData['fName'] ?? "User"} ${initData['lName'] ?? ''}"`).
///
/// Dart's `initData` map starts as a full `user.toJson()` dump (every field
/// the account already has, id/email/mobile/image included) and only
/// overwrites these four before posting — but every other key in that dump is
/// a value the server already has for this session's account, so re-echoing
/// it back changes nothing a profile-update endpoint would act on. Sending
/// just what this screen edits keeps the same effect without modeling the
/// other ~15 passthrough fields for no behavioral gain.
struct AccountSetupProfileRequest: Encodable, Sendable {
    let name: String
    let fName: String?
    let lName: String?
    let dateOfBirth: String
    let gender: String
    /// S3 key of a freshly uploaded profile photo (`initData['image']`).
    var image: String? = nil
}
