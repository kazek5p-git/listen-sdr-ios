# Listen SDR iOS Docs

This directory is the working documentation for the iOS Listen SDR codebase.

## Start here

- `codebase.md` - practical map of the native iOS app, shared Swift package, main flows, tests, and safe change rules.
- `maintenance.md` - short maintenance map: large-file hotspots, refactor cadence, TestFlight checklist, and AI working rules.
- `chromecast-stage1-plan.md` - staged notes for Chromecast-related work.
- `firebase.md` - iOS Firebase/Crashlytics wiring plus the cross-platform Firebase map for iOS and Android.
- `workflow-checklists.md` - practical checklists for features, bugfixes, audio, accessibility, localization, backend changes, shared-core sync, and TestFlight.
- `index.html`, `support.html`, and `privacy-policy.html` - public support/privacy pages that should stay aligned with App Store/TestFlight messaging.

## Documentation rules

- Keep iOS-specific notes in this repo and Android-specific notes in the Android repo.
- Update `codebase.md` when a new subsystem appears, a major flow moves, or ownership changes.
- Update `maintenance.md` when TestFlight, signing, release, or refactor strategy changes.
- Do not document secrets, private signing data, tokens, or local-only credentials.
