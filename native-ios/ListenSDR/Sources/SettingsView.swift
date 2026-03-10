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
          NavigationLink {
            SelectionListView(
              title: L10n.text("settings.accessibility.voiceover_rds_mode"),
              options: VoiceOverRDSAnnouncementMode.allCases.map { mode in
                SelectionListOption(id: mode.rawValue, title: mode.localizedTitle, detail: nil)
              },
              selectedID: radioSession.settings.voiceOverRDSAnnouncementMode.rawValue
            ) { value in
              if let mode = VoiceOverRDSAnnouncementMode(rawValue: value) {
                radioSession.setVoiceOverRDSAnnouncementMode(mode)
              }
            }
          } label: {
            LabeledContent(
              L10n.text("settings.accessibility.voiceover_rds_mode"),
              value: radioSession.settings.voiceOverRDSAnnouncementMode.localizedTitle
            )
          }
          .accessibilityHint(L10n.text("settings.accessibility.voiceover_rds_mode.hint"))
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

        Section {
          if let suggestion = radioSession.fmdxAudioPresetSuggestion {
            VStack(alignment: .leading, spacing: 6) {
              LabeledContent(
                L10n.text("settings.audio.suggestion"),
                value: suggestion.preset.localizedTitle
              )

              Text(suggestion.localizedReason)
                .font(.footnote)
                .foregroundStyle(.secondary)

              if suggestion.preset != radioSession.currentFMDXAudioPreset {
                Button(L10n.text("settings.audio.suggestion.apply")) {
                  radioSession.applyFMDXAudioPreset(suggestion.preset)
                }
              } else {
                Text(L10n.text("settings.audio.suggestion.current"))
                  .font(.footnote)
                  .foregroundStyle(.secondary)
              }
            }
            .accessibilityElement(children: .contain)
          } else {
            Text(L10n.text("settings.audio.suggestion.unavailable"))
              .font(.footnote)
              .foregroundStyle(.secondary)
          }

          NavigationLink {
            SelectionListView(
              title: L10n.text("settings.audio.preset"),
              options: FMDXAudioTuningPreset.selectableCases.map { preset in
                SelectionListOption(
                  id: preset.rawValue,
                  title: preset.localizedTitle,
                  detail: preset.localizedDetail
                )
              },
              selectedID: radioSession.currentFMDXAudioPreset.rawValue
            ) { value in
              if let preset = FMDXAudioTuningPreset(rawValue: value) {
                radioSession.applyFMDXAudioPreset(preset)
              }
            }
          } label: {
            LabeledContent(
              L10n.text("settings.audio.preset"),
              value: radioSession.currentFMDXAudioPreset.localizedTitle
            )
          }
          .accessibilityHint(L10n.text("settings.audio.preset.hint"))

          audioSlider(
            title: L10n.text("settings.audio.startup_buffer"),
            value: radioSession.settings.fmdxAudioStartupBufferSeconds,
            range: 0.25...1.5,
            step: 0.05,
            hintKey: "settings.audio.startup_buffer.hint"
          ) {
            radioSession.setFMDXAudioStartupBufferSeconds($0)
          }

          audioSlider(
            title: L10n.text("settings.audio.max_latency"),
            value: radioSession.settings.fmdxAudioMaxLatencySeconds,
            range: max(0.6, radioSession.settings.fmdxAudioStartupBufferSeconds + 0.25)...3.0,
            step: 0.05,
            hintKey: "settings.audio.max_latency.hint"
          ) {
            radioSession.setFMDXAudioMaxLatencySeconds($0)
          }

          audioSlider(
            title: L10n.text("settings.audio.packet_hold"),
            value: radioSession.settings.fmdxAudioPacketHoldSeconds,
            range: 0.05...0.35,
            step: 0.01,
            hintKey: "settings.audio.packet_hold.hint"
          ) {
            radioSession.setFMDXAudioPacketHoldSeconds($0)
          }

          Button(L10n.text("settings.audio.reset")) {
            radioSession.resetFMDXAudioTuning()
          }
        } header: {
          Text(L10n.text("settings.audio.section"))
        } footer: {
          Text(L10n.text("settings.audio.footer"))
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

  private func audioSlider(
    title: String,
    value: Double,
    range: ClosedRange<Double>,
    step: Double,
    hintKey: String,
    onChange: @escaping (Double) -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      LabeledContent(
        title,
        value: "\(String(format: "%.2f", value)) s"
      )
      Slider(
        value: Binding(
          get: { value },
          set: { onChange($0) }
        ),
        in: range,
        step: step
      )
      .accessibilityHint(L10n.text(hintKey))
    }
  }
}
