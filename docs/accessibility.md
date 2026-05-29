# Listen SDR iOS Accessibility Notes

Accessibility is a primary product requirement for Listen SDR. Treat these rules as part of the UI contract, especially for Receiver, Radios, Settings, and scanner screens.

## DRihelp Audit Baseline

The 2026-05-29 DRihelp audit package is stored outside the repo at:

`C:\Users\Kazek\Desktop\iOS\ListenSDR\Reports\Accessibility\DRihelp-audit-20260529.zip`

The audited TestFlight build was Listen SDR `1.0.1 (105)` on iPhone14,6 / iOS 26.5. The audit found no critical or high-severity issues. The useful medium-priority findings were:

- scrollable content could sit under the bottom tab bar on Receiver, Radios, and Settings screens
- several visible controls had hit targets below 44 x 44 pt
- frequency and radio-search text fields needed stable accessibility labels instead of relying only on placeholders
- repeated generic tuning labels such as Add/Delete needed control-specific labels
- the Settings detail back button needed a clearer label than the tab item label

## Current UI Rules

- Scrollable top-level tab content should use `tabBarScrollClearance()` so the last visible row does not sit under the translucent tab bar.
- Interactive controls should use at least `AppAccessibilityLayout.minimumTouchTarget` and use `comfortableTouchTarget` when a compact control sits in a constrained tuning panel.
- Text fields should have explicit accessibility labels. Placeholder text is only a visual hint, not the accessible name.
- Increment/decrement tuning buttons should include the target control in their label, for example "Increase frequency" or "Decrease Tune step".
- Collapsible section headers should be at least 44 pt high and expose their expanded/collapsed state through `accessibilityValue`.
- Decorative background or spacing views should be hidden from accessibility.

## Manual Verification

For accessibility changes, check at least:

- Receiver tab, top and after scrolling down to FM-DX controls
- Radios tab, search field, directory button, add receiver button, and first visible radio rows
- Settings root and Settings -> Accessibility detail screen
- VoiceOver flick order, button labels, adjustable frequency controls, and whether the bottom tab bar covers the last visible row

DRihelp is useful for regression checks, but a short manual VoiceOver pass is still required before TestFlight when the UI structure changes.
