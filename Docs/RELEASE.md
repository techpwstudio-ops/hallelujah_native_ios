# Release (T76)

**Status: tooling scaffolded; no build has been uploaded.** Everything below needs the
Apple Developer account, signing assets and App Store Connect access that are not in this repo.

## Privacy

- `App/Resources/PrivacyInfo.xcprivacy` declares tracking (ATT), collected data types and the
  required-reason APIs this target calls. **Review against the App Store privacy label and your
  legal copy before each submission.** Third-party SDKs bring their own manifests.

## Build + upload

`.github/workflows/testflight.yml` (manual `workflow_dispatch`) archives the **Release**
configuration and uploads to TestFlight. It needs these repository secrets:

| Secret | What |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` / `P12_PASSWORD` | Apple Distribution certificate (.p12) |
| `PROVISIONING_PROFILE_BASE64` | App Store profile for the bundle id |
| `KEYCHAIN_PASSWORD` | throwaway CI keychain password |
| `APPSTORE_API_KEY_ID` / `APPSTORE_API_ISSUER_ID` / `APPSTORE_API_PRIVATE_KEY` | App Store Connect API key |
| `GOOGLE_SERVICE_INFO_PLIST_BASE64` | Production `GoogleService-Info.plist` |
| `SECRETS_XCCONFIG_BASE64` | `Config/Secrets.xcconfig` |

## Crash monitoring

Firebase Crashlytics (`FirebaseCrashReporter`). Upload dSYMs with the Firebase run script or
`upload-symbols` after each archive.

## Staged rollout

1. TestFlight internal → external beta (≥ 3 days, crash-free sessions ≥ 99.5 %).
2. App Store phased release (7 days). Halt on crash-free < 99 % or a payment regression.

## Migration from the Flutter app (open)

- **Sessions**: Flutter keeps the token in an AES-encrypted Hive box (`secure_storage_box`) with the key
  in Keychain (`hive_encryption_key`). A one-time reader would let existing users stay signed in; today
  they must sign in again. Hook point: `KeychainTokenStore`.
- **Downloads**: Flutter's downloaded files are not picked up; users re-download.
- Same bundle id and App Store listing are required for an in-place upgrade.
