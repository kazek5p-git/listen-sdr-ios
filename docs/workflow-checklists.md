# Listen SDR iOS Workflow Checklists

Use these checklists when changing the native iOS app or shared Swift package. They are intended to keep feature work, refactors, and TestFlight releases predictable.

## Before Changing Code

- Confirm the repo is clean or identify unrelated local changes.
- Read `docs/codebase.md` for the area being changed.
- Decide whether the change is behavior, refactor, documentation, TestFlight metadata, or build-number work. Keep those in separate commits.
- Treat `native-ios/project.yml` as the source of truth for generated Xcode project settings.
- For parity-sensitive logic, change `shared/ListenSDRCore` and fixtures first, then sync Android.
- Prefer focused files or extensions over growing `RadioSessionViewModel.swift`, `SDRBackendClient.swift`, `ReceiverView.swift`, or `SettingsView.swift`.

## Feature Checklist

- Identify the owner layer: SwiftUI view, session model, backend client, audio, shared core, storage, settings, or automation script.
- Keep deterministic decisions in `shared/ListenSDRCore` when Android should mirror the behavior.
- Keep AVAudioSession, networking side effects, SwiftUI, UIKit, and system integration out of shared core.
- Add or update Swift tests for parsing, scanner rules, session policy, settings backup, and pure decision logic.
- Update `docs/codebase.md` when a feature adds a subsystem or moves responsibility.
- Update `docs/maintenance.md` when TestFlight, signing, release flow, or refactor priorities change.

## Bugfix Checklist

- Capture the failing behavior in a test when practical.
- If the bug is backend-specific, isolate the protocol payload or state transition.
- If the bug is audio-related, verify disconnect, reconnect, background playback, lock-screen controls, and AVAudioSession interruptions.
- If the bug is accessibility-related, verify VoiceOver labels, focus order, adjustable controls, rotor behavior, and Magic Tap.
- If the bug affects shared behavior, update shared-core fixtures and Android parity tests.
- After fixing, run the smallest proving check, then a broader check before commit or TestFlight.

## Audio And Call Handling Checklist

- Disconnect must stop receiver audio and release playback resources.
- Phone or communication interruption should mute or pause receiver audio through policy, not disable receiver controls unless the platform requires it.
- After interruption ends, audio should restore according to user settings and session state.
- Now Playing metadata should reflect the current receiver when playback is active.
- System remote commands should remain consistent with connection and recording state.
- Recording state must remain consistent when playback starts, stops, reconnects, or fails.

Suggested verification:

- Unit tests for audio policy or related pure helpers.
- Real iPhone smoke test for connect, disconnect, background, interruption, lock screen, and recording when available.

## Accessibility Checklist

- Important controls have clear VoiceOver labels, hints, values, and actions.
- Focus order is short and predictable, especially on the Receiver tab.
- Status summaries should avoid duplicate focus targets and noisy repeated announcements.
- Adjustable controls expose meaningful increments and current values.
- Magic Tap performs the expected quick action for the current state.
- VoiceOver rotor and shortcut command behavior remain valid.
- UI should remain usable during call/interruption mute state where possible.

Suggested verification:

- VoiceOver review on Receiver, Radios, Settings, Diagnostics, profile editor, directory import, and scanner screens.
- Simulator is acceptable for simple focus checks; use real iPhone for audio and interruption behavior.

## Localization Checklist

- Native iOS strings belong in `native-ios/ListenSDR/Resources/*.lproj/Localizable.strings`.
- Use `L10n.text(..., fallback: ...)` for app strings with a stable key and readable fallback.
- Keep Android translation sync in mind when wording changes are cross-platform.
- Preserve the product wording decision for German tabs: Receiver is `Empfänger`, radio list is `Empfängerliste`.
- Check Polish strings for natural wording because Polish accessibility is a primary use case.

Suggested verification:

- Build or preflight after editing localization resources.
- Manual review in Polish plus one non-Polish language when the changed text is visible.

## Backend Checklist

- Keep protocol side effects in `SDRBackendClient.swift` or focused backend files.
- Move deterministic backend-independent decisions to `shared/ListenSDRCore` when Android should match iOS.
- Verify FM-DX, KiwiSDR, and OpenWebRX behavior when touching shared session or scanner code.
- Directory parsing/search changes should include shared-core tests and fixture updates.
- Avoid hardcoding local receiver assumptions unless they are test fixtures or documented defaults.

Suggested verification:

- Shared Swift package tests for pure logic.
- Native app tests for app-layer integration.
- Manual smoke test with a known working receiver for the affected backend.

## Shared Core And Android Sync Checklist

- Add or update canonical fixtures in `shared/ListenSDRCore/Tests/ListenSDRCoreTests/Fixtures` when behavior contracts change.
- Run `swift test` for `shared/ListenSDRCore` on macOS.
- Sync fixtures into Android with `scripts/Sync-ListenSDRCoreFixtures.ps1` from the Android repo.
- Run Android shared-core parity tests.
- Commit iOS shared-core changes and Android fixture/parity updates separately unless the change is intentionally atomic across repos.

## TestFlight Checklist

- Do not mix build-number bumps with refactors or feature work.
- Update `CURRENT_PROJECT_VERSION` and `MARKETING_VERSION` in `native-ios/project.yml` when preparing a TestFlight build.
- Keep `native-ios/ListenSDR/Info.plist` aligned if the release process requires it.
- Add What to Test notes under `release/testflight/1.0.1-build-<build>/` or the current version/build path.
- Run TestFlight preflight before upload.
- Run the end-to-end TestFlight script only when the repo contains the intended release commit.
- After upload, verify App Store Connect processing, beta groups, and What to Test metadata.

## Minimum Command Matrix

- Docs-only change: `git diff --check`
- Shared pure logic: `swift test` from `shared/ListenSDRCore` on macOS
- Native unsigned build: `powershell -ExecutionPolicy Bypass -File .\scripts\Build-ListenSDR-RemoteUnsigned.ps1`
- TestFlight preflight: `powershell -ExecutionPolicy Bypass -File .\scripts\Test-ListenSDR-TestFlightPreflight.ps1`
- TestFlight upload: `powershell -ExecutionPolicy Bypass -File .\scripts\Run-ListenSDR-TestFlightEndToEnd.ps1`
- Metadata-only publish: `powershell -ExecutionPolicy Bypass -File .\scripts\Publish-ListenSDR-TestFlightMetadata.ps1`
