# Listen SDR Firebase integration

Listen SDR is prepared for Firebase on iOS, but data-collection features remain intentionally opt-in. A build without `GoogleService-Info.plist` starts normally and logs that Firebase is disabled.

## Current scope

- Firebase is wired only in the maintained native iOS app under `native-ios/`.
- The Firebase project is `listen-sdr-kazek5p` (`Listen SDR`).
- The iOS Firebase app is `Listen SDR iOS` with bundle identifier `com.kazek.sdr`.
- `native-ios/project.yml` declares the Firebase iOS SDK Swift Package dependency.
- `FirebaseBootstrap.swift` configures Firebase only when `GoogleService-Info.plist` is bundled.
- `native-ios/ListenSDR/Resources/GoogleService-Info.plist` is the bundled Firebase client configuration.
- Crashlytics collection is disabled by default through `FirebaseCrashlyticsCollectionEnabled: false` and `ListenSDRFirebaseCrashlyticsEnabled: false`.
- Remote Config setup is disabled by default through `ListenSDRFirebaseRemoteConfigEnabled: false`.

## Firebase Console setup

1. Open the Firebase project `listen-sdr-kazek5p`.
2. Confirm the iOS app `Listen SDR iOS` exists with bundle identifier `com.kazek.sdr`.
3. Download `GoogleService-Info.plist` if it must be regenerated.
4. Put the file at `native-ios/ListenSDR/Resources/GoogleService-Info.plist` before generating the Xcode project or running the build.
5. Regenerate the project from `native-ios/` with `xcodegen generate`.
6. Build the app through the normal unsigned or TestFlight workflow.

`GoogleService-Info.plist` is an app configuration file, not a private service-account secret. Do not commit Firebase Admin SDK service-account JSON files, APNs private keys, or Apple signing secrets.

## Enabling Crashlytics

Crashlytics should be enabled only after the public privacy policy and release notes reflect crash diagnostics. To enable it for a production build:

1. Confirm `docs/privacy-policy.html` describes Firebase Crashlytics.
2. Set `ListenSDRFirebaseCrashlyticsEnabled: true` in `native-ios/project.yml`.
3. Keep `FirebaseCrashlyticsCollectionEnabled: false` unless there is a deliberate decision to allow SDK default collection before app bootstrap runs.
4. Add or verify Crashlytics dSYM upload handling for signed release builds.
5. Run a remote unsigned build or TestFlight preflight before release.

The bootstrap sends only coarse app metadata as Crashlytics custom keys: bundle identifier, app version, and build number. It does not attach receiver history, SDR server addresses, recordings, or diagnostic exports.

## Remote Config

Remote Config is present but disabled by default. Enable `ListenSDRFirebaseRemoteConfigEnabled` only when a concrete server-side setting is planned and documented. Avoid using Remote Config for behavior that would surprise users or bypass local privacy choices.

## Push notifications

Firebase Cloud Messaging can be added later, but iOS push still requires Apple Developer/APNs configuration. Firebase does not remove the need for APNs credentials or the iOS push notification entitlement.

## Verification

Use the normal iOS verification path after adding the plist:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-ListenSDRFirebaseConfig.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Build-ListenSDR-RemoteUnsigned.ps1
```
