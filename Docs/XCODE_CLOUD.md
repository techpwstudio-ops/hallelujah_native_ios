# Xcode Cloud: build once, test internally, ship the same build

Two branches, two workflows:

| Branch | Scheme | Backend | Secrets |
| --- | --- | --- | --- |
| `qa` | `GHallelujah Staging` | `qa.api.hallelujah.today` | fixed values committed in `Config/Environments/Staging.xcconfig`; no environment variables needed |
| `prod` | `GHallelujah Production` | `api.hallelujah.today` | workflow environment variables |

The **scheme** picks the backend, not the branch: `GHallelujah Staging` builds with
`Config/Environments/Staging.xcconfig`, `GHallelujah Production` with `Production.xcconfig`. The
branch only decides which workflow runs. `ci_scripts/ci_post_clone.sh` fails the build if a branch
and scheme disagree (`qa` with the Production scheme, or `prod` with anything else), so a
misconfigured workflow cannot ship the wrong backend.

The `prod` workflow archives the Production scheme, publishes to TestFlight internal testing, and that
same build is what you submit for App Store release. Nothing is rebuilt between testing and release,
so what testers ran is what users get.

The repo side is `ci_scripts/ci_post_clone.sh`. The workflows themselves live in Xcode / App Store
Connect (Xcode Cloud workflows are not stored in the repo), so they are set up once by hand.

## What the script does

The Xcode project and `Package.resolved` are committed, so there is no generator, CocoaPods or SDK
install. The script writes the gitignored `Config/Secrets.xcconfig` (`Base.xcconfig` includes it
last, so it overrides the committed defaults) and sets the build number. For the Production scheme
it takes the team and backend secrets from environment variables and fails fast, naming the missing
one. For any other scheme it uses the committed QA values and a default team ID. Firebase needs no
`GoogleService-Info.plist`; it is configured in code.

## One-time setup

Create the two workflows in Xcode -> Product -> Xcode Cloud -> Create Workflow (or App Store Connect
-> Xcode Cloud). Grant access to the GitHub repo once. Both need signing: it is Automatic and
cloud-managed, so Xcode Cloud creates the distribution certificate and profiles for the app and both
extensions (`NotificationServiceExtension`, `SiriIntentsExtension`).

### `qa` workflow

1. **Start condition:** branch changes on `qa`.
2. **Environment:** none.
3. **Actions:** *Archive* -> scheme `GHallelujah Staging`, platform iOS, Deployment Preparation
   *TestFlight (Internal Testing Only)*.
4. **Post-actions:** *TestFlight Internal Testing* -> your QA tester group.

### `prod` workflow

1. **Start condition:** branch changes on `prod`, or manual only if you prefer to release on demand.
2. **Environment** (tick *Secret* on all of them):

   | Variable | Value |
   | --- | --- |
   | `HALLELUJAH_DEVELOPMENT_TEAM` | Apple Team ID |
   | `HALLELUJAH_API_SECRET` | production "secure" header secret |
   | `HALLELUJAH_OTP_SECRET_1` / `_2` | production OTP secrets |
   | `RAZORPAY_KEY_ID` | optional |

3. **Actions:** *Archive* -> scheme `GHallelujah Production`, platform iOS, Deployment Preparation
   *TestFlight and App Store*. Optionally add a *Test* action first on `GHallelujah Development`
   (the unit-test target only builds under Debug).
4. **Post-actions:** *TestFlight Internal Testing* -> your internal tester group.

### App Store Connect

The app record must use bundle id `com.hallelujah.user`, and the capabilities in
`Hallelujah.entitlements` (CarPlay audio, Siri, Sign in with Apple, push, associated domains) must
be enabled on the App ID. CarPlay audio needs Apple's entitlement approval.

QA uses the same bundle id as production (the Firebase console has no `.staging` registration), so
QA and prod builds land in the same TestFlight app and are told apart by build number and, in the
app, by the backend they talk to.

## Releasing

Push to `qa` to get a QA build to testers. Push to `prod` to get a production build; internal testers
get it automatically. To go live, in App Store Connect open the version, select that build, and
submit; no new build. Use phased release as in `Docs/RELEASE.md`.

## Two things that will bite you

- **Marketing version.** It lives in code: `MARKETING_VERSION` in `Config/Shared/Base.xcconfig`.
  Edit and commit it before each App Store release. App Store Connect rejects a version that does
  not increase, so check the live number there and set it higher.
- **Build numbers.** `CURRENT_PROJECT_VERSION` is the minutes since 2026-10-23 plus 335, computed in
  `ci_scripts/ci_post_clone.sh`. Each workflow keeps its own `$CI_BUILD_NUMBER` counter, and qa and
  prod builds share one app and version in App Store Connect, so those counters would collide; a
  clock-based number is unique and always increasing across both. It starts above build 334, the
  last one uploaded before this setup. Do not set a build number by hand.

## Not handled here

- dSYM upload to Crashlytics (add the Firebase upload-symbols run script if you want symbolicated
  crashes).
- `.github/workflows/testflight.yml` and the `Makefile` still reference the old `Hallelujah.xcodeproj`
  and XcodeGen; they are superseded by these workflows for releases.
