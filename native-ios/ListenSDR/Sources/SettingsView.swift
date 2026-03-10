import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var profileStore: ProfileStore
  @EnvironmentObject private var radioSession: RadioSessionViewModel
  @EnvironmentObject private var diagnostics: DiagnosticsStore

  var body: some View {
    NavigationStack {
      List {
        Section(L10n.text("settings.session.section")) {
          Button(L10n.text("settings.session.save_snapshot")) {
            radioSession.saveCurrentSettingsSnapshot()
          }

          Button(L10n.text("settings.session.restore_snapshot")) {
            radioSession.restoreSavedSettingsSnapshot()
          }
          .disabled(!radioSession.hasSavedSettingsSnapshot)

          Text(
            radioSession.hasSavedSettingsSnapshot
              ? L10n.text("settings.session.has_snapshot")
              : L10n.text("settings.session.no_snapshot")
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }
        .appSectionStyle()

        Section(L10n.text("settings.dx.section")) {
          Toggle(
            L10n.text("settings.dx.night_mode"),
            isOn: Binding(
              get: { radioSession.settings.dxNightModeEnabled },
              set: { radioSession.setDXNightModeEnabled($0) }
            )
          )
          .accessibilityHint(L10n.text("settings.dx.night_mode.hint"))

          Toggle(
            L10n.text("settings.dx.auto_filter"),
            isOn: Binding(
              get: { radioSession.settings.autoFilterProfileEnabled },
              set: { radioSession.setAutoFilterProfileEnabled($0) }
            )
          )
          .accessibilityHint(L10n.text("settings.dx.auto_filter.hint"))

          Toggle(
            L10n.text("settings.dx.adaptive_scan"),
            isOn: Binding(
              get: { radioSession.settings.adaptiveScannerEnabled },
              set: { radioSession.setAdaptiveScannerEnabled($0) }
            )
          )
          .accessibilityHint(L10n.text("settings.dx.adaptive_scan.hint"))
        }
        .appSectionStyle()

        Section(L10n.text("settings.accessibility.section")) {
          Toggle(
            L10n.text("settings.accessibility.voiceover_rds"),
            isOn: Binding(
              get: { radioSession.settings.voiceOverAnnouncesRDSChanges },
              set: { radioSession.setVoiceOverRDSAnnouncementsEnabled($0) }
            )
          )
          .accessibilityHint(L10n.text("settings.accessibility.voiceover_rds.hint"))
        }
        .appSectionStyle()

        Section(L10n.text("settings.scanner.section")) {
          VStack(alignment: .leading, spacing: 6) {
            LabeledContent(
              L10n.text("settings.scanner.dwell"),
              value: "\(String(format: "%.1f", radioSession.settings.scannerDwellSeconds)) s"
            )
            Slider(
              value: Binding(
                get: { radioSession.settings.scannerDwellSeconds },
                set: { radioSession.setScannerDwellSeconds($0) }
              ),
              in: 0.5...6,
              step: 0.1
            )
          }

          VStack(alignment: .leading, spacing: 6) {
            LabeledContent(
              L10n.text("settings.scanner.hold"),
              value: "\(String(format: "%.1f", radioSession.settings.scannerHoldSeconds)) s"
            )
            Slider(
              value: Binding(
                get: { radioSession.settings.scannerHoldSeconds },
                set: { radioSession.setScannerHoldSeconds($0) }
              ),
              in: 0.5...12,
              step: 0.1
            )
          }
        }
        .appSectionStyle()

        Section(L10n.text("settings.diagnostics.section")) {
          NavigationLink {
            DiagnosticsView()
          } label: {
            Label(L10n.text("settings.diagnostics.open"), systemImage: "waveform.path.ecg")
          }

          LabeledContent(
            L10n.text("settings.diagnostics.entries"),
            value: "\(diagnostics.entries.count)"
          )
        }
        .appSectionStyle()

        Section(L10n.text("Quick Actions")) {
          Button(L10n.text("Reconnect")) {
            guard let profile = profileStore.selectedProfile else { return }
            radioSession.reconnect(to: profile)
          }
          .disabled(profileStore.selectedProfile == nil)

          Button(L10n.text("Reset DSP")) {
            radioSession.resetDSPSettings()
          }
        }
        .appSectionStyle()
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .navigationTitle(L10n.text("Settings"))
      .appScreenBackground()
    }
  }
}
