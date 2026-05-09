# Listen SDR iOS - maintenance map

This file is the short operational map for keeping the iOS app maintainable while new features are added with AI assistance.

## What lives where

- `native-ios/project.yml` - source of truth for the generated Xcode project. Update build numbers here before TestFlight.
- `native-ios/ListenSDR/Info.plist` - bundle metadata mirrored by the generated project.
- `native-ios/ListenSDR/Sources/RadioSessionViewModel.swift` - main session state, connection lifecycle, audio policy, runtime policy, settings persistence, and VoiceOver quick actions.
- `native-ios/ListenSDR/Sources/SDRBackendClient.swift` - backend protocol clients and transport-level integration.
- `native-ios/ListenSDR/Sources/ReceiverView.swift` - receiver tab UI, connection button, VoiceOver actions, and current receiver summary.
- `native-ios/ListenSDR/Sources/SettingsView.swift` - settings, backup/restore, appearance, and related controls.
- `native-ios/ListenSDR/Resources/*.lproj/Localizable.strings` - native iOS localizations.
- `release/testflight/` - versioned What to Test notes for TestFlight builds.
- `scripts/Run-ListenSDR-TestFlightEndToEnd.ps1` - normal TestFlight publishing path from Windows via the remote Mac.

## Current large-file hotspots

- `RadioSessionViewModel.swift` is about 6200 lines and mixes session lifecycle, backend orchestration, audio policy, settings, scanners, diagnostics, and accessibility actions.
- `SDRBackendClient.swift` is about 5000 lines and mixes multiple backend protocols.
- `ReceiverView.swift` is about 5000 lines and mixes main receiver UI, actions, accessibility, and smaller controls.
- `SettingsView.swift` is about 2300 lines and should be kept from growing further.

## Refactor cadence

- After every 2-3 larger features, do one maintenance pass before the next TestFlight build.
- Keep behavior-preserving refactors separate from feature and release commits.
- Prefer extracting one responsibility at a time, then run the remote unsigned build or TestFlight preflight.
- Do not combine build-number bumps with structural refactors.

## Safe refactor queue

- Extract audio interruption and mute policy from `RadioSessionViewModel.swift` into a focused coordinator or extension.
- Extract runtime foreground/background policy from `RadioSessionViewModel.swift` so call handling and background playback rules stay testable.
- Split `SDRBackendClient.swift` by backend family: KiwiSDR, FM-DX, OpenWebRX, shared transport utilities.
- Extract receiver header/connection-button actions from `ReceiverView.swift` into focused view components.
- Extract Appearance and Backup/Restore sections from `SettingsView.swift` into smaller files.

## Release checklist

- Bump `CFBundleVersion` and `CURRENT_PROJECT_VERSION` in `native-ios/project.yml`.
- Keep `native-ios/ListenSDR/Info.plist` in sync.
- Add `release/testflight/1.0.1-build-<build>/what-to-test.pl.txt` and `what-to-test.en-US.txt`.
- Run `scripts/Run-ListenSDR-TestFlightEndToEnd.ps1` for TestFlight.
- If metadata publishing fails, verify the beta groups through the global `/betaGroups?filter[app]=...` endpoint used by the current scripts.

## AI working rules

- Ask the agent to avoid adding new feature logic directly into the largest files unless it is a small, localized change.
- Ask for a short code map update whenever a feature introduces a new subsystem.
- Ask for a refactor pass after features touching audio, accessibility, localization, or release scripts.
