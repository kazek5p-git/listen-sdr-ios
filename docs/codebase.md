# Listen SDR iOS Codebase Map

This document describes the native iOS app and the shared Swift package. Use it before adding features, fixing bugs, refactoring, or preparing a TestFlight build.

## Repository Shape

- `native-ios/` contains the native SwiftUI iOS app.
- `native-ios/project.yml` is the source of truth for the generated Xcode project and build numbers.
- `native-ios/ListenSDR/Sources/` contains app source files.
- `native-ios/ListenSDR/Resources/` contains Info.plist, entitlements, assets, and `*.lproj/Localizable.strings` files.
- `native-ios/ListenSDRTests/` contains native app tests.
- `shared/ListenSDRCore/` contains pure Swift logic shared by parity fixtures and mirrored by Android.
- `scripts/` contains Windows-side build, sync, TestFlight, metadata, and diagnostics automation.
- `release/testflight/` contains versioned What to Test notes.
- `server/` contains support tooling for feedback/reporting services.
- `.github/workflows/` contains CI workflows for unsigned IPA, signed TestFlight, generated Xcode project sync, and legacy EAS paths.
- `.github/FUNDING.yml` contains GitHub Funding metadata for the author's GitHub profile, PayPal, and BuyCoffee/Postaw Kawę support links.
- `docs/index.html`, `docs/support.html`, and `docs/privacy-policy.html` are public-facing pages and must stay consistent with app metadata and support wording.

The Expo files still exist, but the maintained app path is the native iOS project under `native-ios/`. Root-level Expo files (`App.tsx`, `app.json`, `eas.json`, `package.json`) and `.expo` logs are legacy or support tooling unless a task explicitly targets Expo/EAS.
`Listen-SDR-unsigned-local-latest.ipa`, `native-ios-build-local-latest.log`, and `sideloadlydaemon.log` are local build/install artifacts; do not treat them as canonical source or release metadata.

## Startup Path

1. `ListenSDRApp.swift` creates and wires the main environment objects: accessibility, navigation, profile store, session view model, settings controller, favorites, recordings, history, and diagnostics.
2. `FirebaseBootstrap.swift` performs optional Firebase startup. It exits without side effects when `GoogleService-Info.plist` is not bundled.
3. `ContentView.swift` creates the tab shell: Receiver, Radios, and Settings.
4. `ContentView` also handles scene phase, first-run/tutorial behavior, startup auto-connect, Magic Tap, shortcuts, and AVAudioSession interruption notifications.
5. `RadioSessionViewModel.swift` owns the live receiver session and receives runtime policy updates from `ContentView`.
6. `SettingsViewController.swift` binds settings-related stores to the session model.

When debugging startup or state binding, follow this order: `ListenSDRApp`, `ContentView`, `RadioSessionViewModel`, then the specific tab or store.

## Main App Layer

Important files under `native-ios/ListenSDR/Sources/`:

- `RadioSessionViewModel.swift` is the main session state and orchestration layer. It owns connection lifecycle, backend orchestration, runtime policy, audio policy, scanners, diagnostics, settings persistence, and accessibility actions.
- `ReceiverView.swift` is the main receiver tab, including connection controls, current receiver summary, tuning controls, scanner UI, VoiceOver actions, and receiver-specific panels.
- `RadiosView.swift` and `ReceiverDirectoryView.swift` handle receiver lists, history, favorites, directory browsing, import, and selection.
- `SettingsView.swift` contains user settings, audio controls, accessibility options, appearance/skins, backup/restore, and related settings sections.
- `SettingsViewController.swift` bridges settings state and stores into the UI/session layer.
- `FirebaseBootstrap.swift` configures Firebase Core, Release-controlled Crashlytics collection, and optional Remote Config when a Firebase plist is present.
- `ContentView.swift` owns tab navigation, lifecycle hooks, startup auto-connect, and interruption notifications.
- `AppNavigationState.swift`, `AppShortcutCommandCenter.swift`, and `ListenSDRAppShortcuts.swift` support app navigation and shortcuts.
- `UnavailableContentView.swift`, `NativeAdjustableChipControl.swift`, `VoiceOverRotorControl.swift`, `ProfileEditorView.swift`, and other small views are examples of focused files that should guide future extraction.
- `ShareSheet.swift` is the UIKit bridge for iOS sharing flows.
- `StableAnnouncementGate.swift` throttles repeated accessibility announcements and should be considered when changing status speech.

Rule: avoid adding new large feature blocks to `RadioSessionViewModel.swift`, `SDRBackendClient.swift`, `ReceiverView.swift`, or `SettingsView.swift` unless the change is small and local.

## Backend And Receiver Integration

- `SDRBackend.swift` defines backend identity and common backend concepts.
- `SDRConnectionProfile.swift` defines connection profile data.
- `SDRBackendClient.swift` contains backend transport integration for KiwiSDR, FM-DX Webserver, OpenWebRX, and shared protocol behavior.
- `BackendTelemetry.swift` models runtime backend telemetry.
- `FMDXBandScanner.swift`, `FMDXCapabilities*`, `FMDXPresetScriptParser.swift`, and `FMDXStationListResolverTests.swift` cover FM-DX-specific scanning, capabilities, presets, and station-list behavior.
- `FMDXCapabilitiesPolicyBridge.swift`, `FMDXCapabilitiesSyncBridge.swift`, and `FMDXTelemetrySyncBridge.swift` adapt shared FM-DX core decisions into the app/session layer.
- `KiwiNoiseProcessing.swift`, `KiwiWaterfallProcessing.swift`, and `KiwiWaterfallViewport.swift` cover Kiwi-specific waterfall and signal behavior.
- `ReceiverDirectory.swift`, `ReceiverDirectoryView.swift`, `ReceiverDataCache.swift`, and `DirectoryChangeNotificationService.swift` cover receiver directory download, cache, browsing, and update notifications.
- `ReceiverLinkImport.swift` and `ImportReceiverLinkView.swift` support importing receiver links into profiles.

Backend parsing or deterministic decisions should move into `shared/ListenSDRCore` when they need parity with Android. Platform networking and AVAudioSession behavior stay in the app layer.

## Audio, Calls, Recording, And System Controls

- `AudioOutputEngine.swift` owns iOS audio output behavior.
- `AudioDecoders.swift` and `AudioPCMUtilities.swift` handle decoding and PCM helper logic.
- `RadioSessionAudioMutePolicy.swift` defines call/interruption mute behavior separately from UI enablement.
- `RadioSessionRuntimePolicy.swift` defines foreground/background and runtime state decisions.
- `NowPlayingMetadataController.swift` updates lock-screen/Now Playing metadata.
- `SystemRemoteCommandController.swift` handles system media controls.
- `AudioRecordingStore.swift`, `RecordingDestinationStore.swift`, `RecordingFolderPicker.swift`, and `RecordingsView.swift` handle recording files, destination selection, and recordings UI.
- `SpeechLoudnessLeveler.swift` and `SpeechLoudnessLevelingMode.swift` support spoken-feedback loudness behavior.

During phone calls or communication interruptions, prefer muting receiver audio through policy while keeping receiver controls usable unless there is a specific platform restriction.

## Data, Settings, And Local State

- `ProfileStore.swift` stores receiver profiles and selected profile state.
- `FavoritesStore.swift` stores favorite receivers.
- `ListeningHistoryStore.swift` stores recent receivers, recent listening records, and recent frequencies.
- `RadioSessionSettings.swift` defines settings and related models.
- `RadioSessionSettingsBackupCodec.swift`, `SettingsBackupDocument.swift`, and settings backup/restore UI handle import/export of app settings.
- `DiagnosticsStore.swift`, `DiagnosticsView.swift`, and `DiagnosticsExportBuilder.swift` manage diagnostic logs and exports.
- `ListenSDRFeedbackFormView.swift` and `ListenSDRFeedbackSender.swift` support in-app feedback/report submission.
- `FrequencyPresetStore.swift`, `BandTuningProfile.swift`, `ConnectionNetworkPolicy.swift`, and `ReceiverIdentity.swift` support saved tuning, runtime connection policy, and stable receiver identity behavior.
- `DemodulationMode.swift`, `TuneStepPreferenceMode.swift`, and `ChannelScannerSignalCore.swift` define app-facing session, tuning, and scanner signal concepts that overlap with shared-core behavior.

Storage and backup changes should include tests for migration, decoding, and failure behavior when practical.

## UI, Accessibility, Theme, And Localization

- `L10n.swift` reads localized strings and fallback text.
- `native-ios/ListenSDR/Resources/*.lproj/Localizable.strings` are the native iOS localization files.
- `AppAccessibility.swift`, `VoiceOverRotorControl.swift`, `NativeAdjustableChipControl.swift`, and accessibility-related actions in views support VoiceOver-first usage.
- `AppTheme.swift`, `CustomThemeEditorView.swift`, and skin-related settings define appearance and custom themes.
- `AppTutorialView.swift` contains first-run/tutorial UI.
- `SupportDevelopmentCard.swift` contains support/donation UI for BuyCoffee/Postaw Kawę, PayPal, and the author's GitHub profile.

Accessibility is a product requirement, not an optional polish pass. Any UI change should check VoiceOver order, labels, adjustable controls, Magic Tap behavior, and whether controls remain usable during audio interruptions.
Use `docs/accessibility.md` as the current accessibility implementation note. It documents the DRihelp audit baseline, minimum touch-target constants, tab-bar scroll clearance, and required manual checks.

## Shared Swift Core And Android Parity

`shared/ListenSDRCore/` contains pure Swift logic that Android mirrors in its `shared-core/` module. Keep platform frameworks out of this package.

Typical shared-core areas:

- frequency parsing and formatting
- backend/runtime policy decisions
- session tuning and restore decisions
- FM-DX scanner and capabilities rules
- receiver directory parsing/search/selection
- receiver link import
- Kiwi passband/waterfall processing
- saved settings snapshots and fixture contracts

When shared behavior changes, update Swift tests and fixtures first, then sync Android fixtures and run Android parity tests.

## Automation, Public Pages, And Support Services

- `.github/workflows/sync-xcodeproj.yml` keeps the generated Xcode project aligned with `native-ios/project.yml`.
- `.github/workflows/ios-unsigned-ipa.yml` builds unsigned IPA artifacts for Sideloadly-style installation.
- `.github/workflows/ios-signed-testflight.yml` builds signed IPA artifacts and can upload to TestFlight when secrets are configured.
- `.github/workflows/eas-ios.yml` and `eas-android-release.yml` are legacy Expo/EAS paths; do not use them as the primary native iOS release path unless intentionally reviving EAS.
- `docs/firebase.md` documents the Firebase setup, including the required `GoogleService-Info.plist`, Crashlytics privacy guard, dSYM upload flow, and future push-notification constraints.
- `server/listen-sdr-feedback-bot/` contains the Telegram/reporting feedback bot and service file for the support pipeline.
- `.github/FUNDING.yml` should stay aligned with `SupportDevelopmentCard.swift`, the legacy Expo support panel, and `docs/support.html`.
- `scripts/Deploy-ListenSDR-FeedbackBot.ps1`, `Check-ListenSDRTelegramReports.ps1`, and related Telegram scripts operate the feedback/reporting side channel.
- Public HTML files in `docs/` should be updated when support, privacy, or public product wording changes.

Script inventory by responsibility:

- Build/install/sync: `scripts/Build-And-Install-ListenSDR.ps1`, `scripts/Build-ListenSDR-RemoteUnsigned.ps1`, `scripts/Sync-ListenSDR-ToMac.ps1`, and `scripts/start-ios-live.ps1`.
- TestFlight release flow: `scripts/Run-ListenSDR-TestFlight.ps1`, `scripts/Run-ListenSDR-RemoteTestFlight.ps1`, `scripts/Run-ListenSDR-TestFlightEndToEnd.ps1`, `scripts/Test-ListenSDR-TestFlightPreflight.ps1`, `scripts/Publish-ListenSDR-TestFlightMetadata.ps1`, `scripts/Publish-ListenSDR-PublicTestFlight.ps1`, `scripts/New-ListenSDR-TestFlightReleaseNotes.ps1`, and `scripts/Publish-ListenSDR.ps1`.
- App Store Connect checks/secrets: `scripts/Check-ListenSDR-AppStoreConnect.ps1`, `scripts/Check-ListenSDR-TestFlightReports.ps1`, `scripts/Check-ListenSDR-TestFlightStatus.ps1`, `scripts/Ensure-ListenSDR-AppStoreProfile.ps1`, and `scripts/Set-ListenSDR-TestFlightSecrets.ps1`.
- Feedback/reporting: `scripts/Deploy-ListenSDR-FeedbackBot.ps1`, `scripts/Check-ListenSDRTelegramReports.ps1`, `scripts/Get-ListenSDRTelegramReports.ps1`, `scripts/Read-ListenSDR-TweeseCakeTelegramChat.py`, `scripts/Set-ListenSDRTelegramReportsSecret.ps1`, and `scripts/Test-ListenSDR-TestFlightWebhookHealth.ps1`.

## Test And Verification Commands

Use the smallest command that proves the change, then run broader checks before TestFlight.

- Swift package tests: run `swift test` from `shared/ListenSDRCore` on macOS.
- Native unsigned build from Windows: `powershell -ExecutionPolicy Bypass -File .\scripts\Build-ListenSDR-RemoteUnsigned.ps1`
- Firebase wiring check: `powershell -ExecutionPolicy Bypass -File .\scripts\Test-ListenSDRFirebaseConfig.ps1`
- TestFlight preflight: `powershell -ExecutionPolicy Bypass -File .\scripts\Test-ListenSDR-TestFlightPreflight.ps1`
- End-to-end TestFlight upload: `powershell -ExecutionPolicy Bypass -File .\scripts\Run-ListenSDR-TestFlightEndToEnd.ps1`
- Metadata-only TestFlight publish: `powershell -ExecutionPolicy Bypass -File .\scripts\Publish-ListenSDR-TestFlightMetadata.ps1`

For UI or accessibility changes, verify on iPhone or simulator with VoiceOver-oriented checks. For audio/background behavior, prefer a real device.

## Safe Change Rules

- Keep behavior changes, refactors, and build-number bumps in separate commits.
- Update `native-ios/project.yml` as the source of truth for generated Xcode project settings.
- Do not hand-edit generated Xcode settings without reflecting them in `project.yml`.
- Extract one responsibility at a time from large files.
- Keep backend protocol side effects in app-layer clients and pure decisions in `shared/ListenSDRCore`.
- Add tests for pure logic, parsing, scanner rules, settings backup, audio policy, and parity fixtures.
- Update this file when ownership or major flow changes.

## Known Maintenance Debt

As of the current maintenance pass, the largest iOS risks are:

- `RadioSessionViewModel.swift`, `SDRBackendClient.swift`, `ReceiverView.swift`, and `SettingsView.swift` remain large.
- Backend client responsibilities should gradually split by backend family.
- Audio interruption/runtime policy should stay isolated and tested as it evolves.
- Settings and appearance sections should continue moving into focused view files.
- Release/TestFlight automation is powerful but should be documented whenever script behavior changes.
