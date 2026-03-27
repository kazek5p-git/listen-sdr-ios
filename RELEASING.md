## Release Workflow

This project is the public source of truth for Listen SDR releases.

### Source of truth

- iOS remains the product source of truth.
- Shared behavior should continue to follow the `iOS -> shared logic -> Android` direction.
- Android public distribution must stay aligned with iOS release naming and versioning.

### Public distribution rules

- The public iOS beta channel is TestFlight.
- The public Android download must be published as a GitHub Release asset in this public repository.
- Do not publish public Android download links from the private `android-starter-app` repository.
- FM-DX descriptions, landing pages, support pages, and other public materials should point Android users to the public APK hosted from this repository.

### Current Android public release convention

- GitHub Release tag example: `android-v1.0.1-build-3`
- Asset name: `ListenSDR-android-release.apk`
- Public download pattern:
  `https://github.com/kazek5p-git/listen-sdr-ios/releases/download/<tag>/ListenSDR-android-release.apk`

### Release hygiene

- Keep release notes for iOS and Android consistent.
- Keep public links stable and human-readable.
- Before sharing any Android link, verify that it resolves from the public repository and does not return `404`.
- If a future public `listen-sdr-android` repository is ever created, treat it as a distribution repository, not as a new source of truth.
