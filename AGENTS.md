# Listen SDR iOS agent rules

- Keep new features split by responsibility. Do not keep expanding `RadioSessionViewModel.swift`, `SDRBackendClient.swift`, `ReceiverView.swift`, or `SettingsView.swift` unless the change is small and local.
- When a feature touches audio, accessibility, TestFlight, skins, or localization, update `docs/maintenance.md` if ownership or release flow changes.
- Keep behavior-preserving refactors separate from feature changes and TestFlight build-number bumps.
- Treat `native-ios/project.yml` as the source of truth for generated Xcode project settings.
- Prefer extracting one focused Swift view, backend client, or coordinator at a time, then verify with the remote unsigned build or TestFlight preflight.
