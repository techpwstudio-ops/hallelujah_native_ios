# Xcode Cloud: build once, test internally, ship the same build

One workflow archives the **GHallelujah Production** scheme, publishes the build to TestFlight
internal testing, and that same build is what you submit for App Store release. Nothing is rebuilt
between testing and release, so what testers ran is what users get.

The repo side is `ci_scripts/ci_post_clone.sh`. The workflow itself lives in Xcode / App Store
Connect (Xcode Cloud workflows are not stored in the repo), so it is set up once by hand.

## What the script does

The Xcode project and `Package.resolved` are committed, so there is no generator, CocoaPods or SDK
install. The script writes the gitignored `Config/Secrets.xcconfig` from environment variables
(`Base.xcconfig` includes it last, so it overrides the committed defaults) and sets the build number
from `$CI_BUILD_NUMBER`. It fails fast, naming the missing variable, if a Production build lacks the
team or backend secrets. Firebase needs no `GoogleService-Info.plist`; it is configured in code.

## One-time setup

1. Xcode -> Product -> Xcode Cloud -> Create Workflow (or App Store Connect -> Xcode Cloud). Grant
   access to the GitHub repo.
2. **Environment** (tick *Secret* on all except `BUILD_NUMBER_OFFSET`):

   | Variable | Value |
   | --- | --- |
   | `HALLELUJAH_DEVELOPMENT_TEAM` | Apple Team ID |
   | `HALLELUJAH_API_SECRET` | production "secure" header secret |
   | `HALLELUJAH_OTP_SECRET_1` / `_2` | production OTP secrets |
   | `RAZORPAY_KEY_ID` | optional |
   | `BUILD_NUMBER_OFFSET` | optional, see below |

3. **Start condition:** branch `main` (changes to files), or manual only if you prefer to release on
   demand.
4. **Actions:** *Archive* -> scheme `GHallelujah Production`, platform iOS, Deployment Preparation
   *TestFlight and App Store*. Optionally add a *Test* action first on `GHallelujah Development`
   (the unit-test target only builds under Debug).
5. **Post-actions:** *TestFlight Internal Testing* -> pick your internal tester group.
6. Signing is Automatic and cloud-managed; Xcode Cloud creates the distribution certificate and
   profiles for the app and both extensions (`NotificationServiceExtension`, `SiriIntentsExtension`).
7. Make sure the App Store Connect app record uses bundle id `com.hallelujah.user`, and that the
   capabilities in `Hallelujah.entitlements` (CarPlay audio, Siri, Sign in with Apple, push,
   associated domains) are enabled on the App ID. CarPlay audio needs Apple's entitlement approval.

## Releasing

Internal testers get the build automatically. To go live, in App Store Connect open the version,
select that build, and submit; no new build. Use phased release as in `Docs/RELEASE.md`.

## Two things that will bite you

- **Marketing version.** It lives in code: `MARKETING_VERSION` in `Config/Shared/Base.xcconfig`.
  Edit and commit it before each App Store release. App Store Connect rejects a version that does
  not increase, so check the live number there and set it higher.
- **Build numbers.** `CURRENT_PROJECT_VERSION` becomes `$CI_BUILD_NUMBER + BUILD_NUMBER_OFFSET`.
  The offset defaults to `334` in `ci_scripts/ci_post_clone.sh` (the last build already in App
  Store Connect), so the first Xcode Cloud build is 335 and each later one counts up. Change that
  default if a higher build is uploaded outside Xcode Cloud, or if the workflow is recreated
  (which resets `$CI_BUILD_NUMBER` to 1). Setting `BUILD_NUMBER_OFFSET` in the workflow overrides it.

## Not handled here

- dSYM upload to Crashlytics (add the Firebase upload-symbols run script if you want symbolicated
  crashes).
- `.github/workflows/testflight.yml` and the `Makefile` still reference the old `Hallelujah.xcodeproj`
  and XcodeGen; they are superseded by this workflow for releases.
