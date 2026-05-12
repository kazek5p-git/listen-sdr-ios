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

The Expo files still exist, but the maintained app path is the native iOS project under `native-ios/`.

## Startup Path

1. `ListenSDRApp.swift` creates and wires the main environment objects: accessibility, navigation, profile store, session view model, settings controller, favorites, recordings, history, and diagnostics.
2. `ContentView.swift` creates the tab shell: Receiver, Radios, and Settings.
3. `ContentView` also handles scene phase, first-run/tutorial behavior, startup auto-connect, Magic Tap, shortcuts, and AVAudioSession interruption notifications.
4. `RadioSessionViewModel.swift` owns the live receiver session and receives runtime policy updates from `ContentView`.
5. `SettingsViewController.swift` binds settings-related stores to the session model.

When debugging startup or state binding, follow this order: `ListenSDRApp`, `ContentView`, `RadioSessionViewModel`, then the specific tab or store.

## Main App Layer

Important files under `native-ios/ListenSDR/Sources/`:

- `RadioSessionViewModel.swift` is the main session state and orchestration layer. It owns connection lifecycle, backend orchestration, runtime policy, audio policy, scanners, diagnostics, settings persistence, and accessibility actions.
- `ReceiverView.swift` is the main receiver tab, including connection controls, current receiver summary, tuning controls, scanner UI, VoiceOver actions, and receiver-specific panels.
- `RadiosView.swift` and `ReceiverDirectoryView.swift` handle receiver lists, history, favorites, directory browsing, import, and selection.
- `SettingsView.swift` contains user settings, audio controls, accessibility options, appearance/skins, backup/restore, and related settings sections.
- `SettingsViewController.swift` bridges settings state and stores into the UI/session layer.
- `ContentView.swift` owns tab navigation, lifecycle hooks, startup auto-connect, and interruption notifications.
- `AppNavigationState.swift`, `AppShortcutCommandCenter.swift`, and `ListenSDRAppShortcuts.swift` support app navigation and shortcuts.
- `UnavailableContentView.swift`, `NativeAdjustableChipControl.swift`, `VoiceOverRotorControl.swift`, and other small views are examples of focused files that should guide future extraction.

Rule: avoid adding new large feature blocks to `RadioSessionViewModel.swift`, `SDRBackendClient.swift`, `ReceiverView.swift`, or `SettingsView.swift` unless the change is small and local.

## Backend And Receiver Integration

- `SDRBackend.swift` defines backend identity and common backend concepts.
- `SDRConnectionProfile.swift` defines connection profile data.
- `SDRBackendClient.swift` contains backend transport integration for KiwiSDR, FM-DX Webserver, OpenWebRX, and shared protocol behavior.
- `BackendTelemetry.swift` models runtime backend telemetry.
- `FMDXBandScanner.swift`, `FMDXCapabilities*`, `FMDXPresetScriptParser.swift`, and `FMDXStationListResolverTests.swift` cover FM-DX-specific scanning, capabilities, presets, and station-list behavior.
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

Storage and backup changes should include tests for migration, decoding, and failure behavior when practical.

## UI, Accessibility, Theme, And Localization

- `L10n.swift` reads localized strings and fallback text.
- `native-ios/ListenSDR/Resources/*.lproj/Localizable.strings` are the native iOS localization files.
- `AppAccessibility.swift`, `VoiceOverRotorControl.swift`, `NativeAdjustableChipControl.swift`, and accessibility-related actions in views support VoiceOver-first usage.
- `AppTheme.swift`, `CustomThemeEditorView.swift`, and skin-related settings define appearance and custom themes.
- `AppTutorialView.swift` contains first-run/tutorial UI.
- `SupportDevelopmentCard.swift` contains support/donation UI.

Accessibility is a product requirement, not an optional polish pass. Any UI change should check VoiceOver order, labels, adjustable controls, Magic Tap behavior, and whether controls remain usable during audio interruptions.

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

## Test And Verification Commands

Use the smallest command that proves the change, then run broader checks before TestFlight.

- Swift package tests: run `swift test` from `shared/ListenSDRCore` on macOS.
- Native unsigned build from Windows: `powershell -ExecutionPolicy Bypass -File .\scripts\Build-ListenSDR-RemoteUnsigned.ps1`
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
