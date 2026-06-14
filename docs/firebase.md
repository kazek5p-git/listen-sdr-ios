# Listen SDR Firebase integration

Listen SDR is prepared for Firebase on iOS, but data-collection features remain intentionally opt-in. A build without `GoogleService-Info.plist` starts normally and logs that Firebase is disabled.

## Current scope

- Firebase is wired only in the maintained native iOS app under `native-ios/`.
- The Firebase project is `listen-sdr-kazek5p` (`Listen SDR`).
- The iOS Firebase app is `Listen SDR iOS` with bundle identifier `com.kazek.sdr`.
- `native-ios/project.yml` declares the Firebase iOS SDK Swift Package dependency.
- `FirebaseBootstrap.swift` configures Firebase only when `GoogleService-Info.plist` is bundled.
- `native-ios/ListenSDR/Resources/GoogleService-Info.plist` is the bundled Firebase client configuration.
- Crashlytics collection is enabled for Release builds through `ListenSDRFirebaseCrashlyticsEnabled`, while SDK default collection remains disabled through `FirebaseCrashlyticsCollectionEnabled: false` until app bootstrap applies the app-specific flag.
- Crashlytics dSYM upload is wired as an Xcode post-build script and is controlled by `LISTENSDR_CRASHLYTICS_UPLOAD_SYMBOLS`.
- Unsigned local/GitHub IPA builds explicitly set `LISTENSDR_CRASHLYTICS_UPLOAD_SYMBOLS=NO` and `LISTENSDR_FIREBASE_CRASHLYTICS_ENABLED=false`.
- Remote Config setup is disabled by default through `ListenSDRFirebaseRemoteConfigEnabled: false`.

## Firebase Console setup

1. Open the Firebase project `listen-sdr-kazek5p`.
2. Confirm the iOS app `Listen SDR iOS` exists with bundle identifier `com.kazek.sdr`.
3. Download `GoogleService-Info.plist` if it must be regenerated.
4. Put the file at `native-ios/ListenSDR/Resources/GoogleService-Info.plist` before generating the Xcode project or running the build.
5. Regenerate the project from `native-ios/` with `xcodegen generate`.
6. Build the app through the normal unsigned or TestFlight workflow.

`GoogleService-Info.plist` is an app configuration file, not a private service-account secret. Do not commit Firebase Admin SDK service-account JSON files, APNs private keys, or Apple signing secrets.

## Crashlytics

Crashlytics is prepared for signed Release/TestFlight builds:

1. `docs/privacy-policy.html` describes Firebase Crashlytics.
2. Release builds set `LISTENSDR_FIREBASE_CRASHLYTICS_ENABLED=true`.
3. Unsigned builds override that flag to `false`.
4. The post-build script runs Firebase's `Crashlytics/run` script only when `LISTENSDR_CRASHLYTICS_UPLOAD_SYMBOLS=YES`.
5. The script declares the dSYM, dSYM DWARF binary, dSYM Info.plist, Firebase plist, and executable as input files for Xcode's script sandboxing.
6. Run a remote unsigned build or TestFlight preflight before release.

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
