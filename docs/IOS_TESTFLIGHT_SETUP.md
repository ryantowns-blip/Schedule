# Web Schedule Manager — iOS/TestFlight setup

The shared Flutter application now compiles successfully for iOS in GitHub Actions using an unsigned device build. The remaining step before installing on an iPhone or distributing through TestFlight is Apple code signing and App Store Connect authentication.

## Apple requirements

1. Active Apple Developer Program membership.
2. An App Store Connect app record for **Web Schedule Manager**.
3. A unique iOS bundle identifier. Recommended format: `com.ryantowns.webschedulemanager` if available.
4. An Apple Distribution certificate and matching private key exported as a password-protected `.p12` file.
5. An App Store provisioning profile for the bundle identifier.
6. An App Store Connect API key with access to upload builds.

## GitHub Actions secrets used by the TestFlight workflow

The signing workflow is designed to read all sensitive values from GitHub Actions secrets. Never commit certificates, provisioning profiles, API keys, passwords, or FAA credentials to the repository.

Required secrets:

- `APPLE_TEAM_ID`
- `IOS_BUNDLE_ID`
- `IOS_CERTIFICATE_BASE64` — base64 encoded `.p12`
- `IOS_CERTIFICATE_PASSWORD`
- `IOS_PROVISIONING_PROFILE_BASE64` — base64 encoded `.mobileprovision`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_BASE64` — base64 encoded `.p8`

## Current iOS status

- Flutter/iOS compilation: PASS
- Shared application tests: PASS
- WebView code compiles on iOS: PASS
- Calendar plugin compiles on iOS: PASS
- Calendar permission descriptions are injected into `Info.plist` during CI.
- App display name is set to **Web Schedule Manager** during CI.
- Signed IPA/TestFlight upload: pending Apple signing credentials.

## Important compatibility rule

The Android Build #94 baseline is preserved separately on `stable/android-build-94`. iOS work is performed on `v0.8.0-ios` so signing and Apple-specific changes do not endanger the known-good Android checkpoint.
