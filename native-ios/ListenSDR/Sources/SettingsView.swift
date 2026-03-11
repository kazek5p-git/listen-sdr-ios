import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var settingsController: SettingsViewController

  var body: some View {
    NavigationStack {
      Form {
        sessionSection
        dxSection
        tuningSection
        accessibilitySection
        historySection
        scannerSection
        audioSection
        diagnosticsSection
        quickActionsSection
      }
      .scrollContentBackground(.hidden)
      .navigationTitle(L10n.text("Settings"))
      .appScreenBackground()
    }
  }

  private var sessionSection: some View {
    Section {
      FocusRetainingButton {
        settingsController.saveCurrentSettingsSnapshot()
      } label: {
        Text(L10n.text("settings.session.save_snapshot"))
      }

      FocusRetainingButton {
        settingsController.restoreSavedSettingsSnapshot()
      } label: {
        Text(L10n.text("settings.session.restore_snapshot"))
      }
      .disabled(!settingsController.state.hasSavedSettingsSnapshot)

      Text(
        settingsController.state.hasSavedSettingsSnapshot
          ? L10n.text("settings.session.has_snapshot")
          : L10n.text("settings.session.no_snapshot")
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
    } header: {
      AppSectionHeader(title: L10n.text("settings.session.section"))
    }
    .appSectionStyle()
  }

  private var dxSection: some View {
    Section {
      Toggle(
        L10n.text("settings.dx.night_mode"),
        isOn: Binding(
          get: { settingsController.state.dxNightModeEnabled },
          set: { settingsController.setDXNightModeEnabled($0) }
        )
      )
      .accessibilityHint(L10n.text("settings.dx.night_mode.hint"))

      Toggle(
        L10n.text("settings.dx.adaptive_scan"),
        isOn: Binding(
          get: { settingsController.state.adaptiveScannerEnabled },
          set: { settingsController.setAdaptiveScannerEnabled($0) }
        )
      )
      .accessibilityHint(L10n.text("settings.dx.adaptive_scan.hint"))
    } header: {
      AppSectionHeader(title: L10n.text("settings.dx.section"))
    }
    .appSectionStyle()
  }

  private var tuningSection: some View {
    Section {
      NavigationLink {
        SelectionListView(
          title: L10n.text("settings.tuning.direction"),
          options: TuningGestureDirection.allCases.map { direction in
            SelectionListOption(
              id: direction.rawValue,
              title: direction.localizedTitle,
              detail: direction.localizedDetail
            )
          },
          selectedID: settingsController.state.tuningGestureDirection.rawValue
        ) { value in
          if let direction = TuningGestureDirection(rawValue: value) {
            settingsController.setTuningGestureDirection(direction)
          }
        }
      } label: {
        LabeledContent(
          L10n.text("settings.tuning.direction"),
          value: settingsController.state.tuningGestureDirection.localizedTitle
        )
      }
      .accessibilityHint(L10n.text("settings.tuning.direction.hint"))

      NavigationLink {
        SelectionListView(
          title: L10n.text("settings.tuning.global_step"),
          options: settingsController.state.tuneStepOptions.map { stepHz in
            SelectionListOption(
              id: "\(stepHz)",
              title: FrequencyFormatter.tuneStepText(fromHz: stepHz),
              detail: nil
            )
          },
          selectedID: "\(settingsController.state.tuneStepHz)"
        ) { value in
          if let stepHz = Int(value) {
            settingsController.setTuneStepHz(stepHz)
          }
        }
      } label: {
        LabeledContent(
          L10n.text("settings.tuning.global_step"),
          value: FrequencyFormatter.tuneStepText(fromHz: settingsController.state.tuneStepHz)
        )
      }
      .accessibilityHint(L10n.text("settings.tuning.global_step.hint"))
      .disabled(settingsController.state.tuneStepOptions.isEmpty)
    } header: {
      AppSectionHeader(title: L10n.text("settings.tuning.section"))
    }
    .appSectionStyle()
  }

  private var accessibilitySection: some View {
    Section {
      NavigationLink {
        SelectionListView(
          title: L10n.text("settings.accessibility.voiceover_rds_mode"),
          options: VoiceOverRDSAnnouncementMode.allCases.map { mode in
            SelectionListOption(id: mode.rawValue, title: mode.localizedTitle, detail: nil)
          },
          selectedID: settingsController.state.voiceOverRDSAnnouncementMode.rawValue
        ) { value in
          if let mode = VoiceOverRDSAnnouncementMode(rawValue: value) {
            settingsController.setVoiceOverRDSAnnouncementMode(mode)
          }
        }
      } label: {
        LabeledContent(
          L10n.text("settings.accessibility.voiceover_rds_mode"),
          value: settingsController.state.voiceOverRDSAnnouncementMode.localizedTitle
        )
      }
      .accessibilityHint(L10n.text("settings.accessibility.voiceover_rds_mode.hint"))
    } header: {
      AppSectionHeader(title: L10n.text("settings.accessibility.section"))
    }
    .appSectionStyle()
  }

  private var historySection: some View {
    Section {
      Toggle(
        L10n.text("settings.history.open_receiver_after_restore"),
        isOn: Binding(
          get: { settingsController.state.openReceiverAfterHistoryRestore },
          set: { settingsController.setOpenReceiverAfterHistoryRestore($0) }
        )
      )
      .accessibilityHint(L10n.text("settings.history.open_receiver_after_restore.hint"))
    } header: {
      AppSectionHeader(title: L10n.text("settings.history.section"))
    }
    .appSectionStyle()
  }

  private var scannerSection: some View {
    Section {
      VStack(alignment: .leading, spacing: 6) {
        LabeledContent(
          L10n.text("settings.scanner.dwell"),
          value: "\(String(format: "%.1f", settingsController.state.scannerDwellSeconds)) s"
        )
        Slider(
          value: Binding(
            get: { settingsController.state.scannerDwellSeconds },
            set: { settingsController.setScannerDwellSeconds($0) }
          ),
          in: 0.5...6,
          step: 0.1
        )
      }

      VStack(alignment: .leading, spacing: 6) {
        LabeledContent(
          L10n.text("settings.scanner.hold"),
          value: "\(String(format: "%.1f", settingsController.state.scannerHoldSeconds)) s"
        )
        Slider(
          value: Binding(
            get: { settingsController.state.scannerHoldSeconds },
            set: { settingsController.setScannerHoldSeconds($0) }
          ),
          in: 0.5...12,
          step: 0.1
        )
      }
    } header: {
      AppSectionHeader(title: L10n.text("settings.scanner.section"))
    }
    .appSectionStyle()
  }

  private var audioSection: some View {
    Section {
      NavigationLink {
        SelectionListView(
          title: L10n.text("settings.audio.suggestion_scope"),
          options: AudioSuggestionScope.allCases.map { scope in
            SelectionListOption(
              id: scope.rawValue,
              title: scope.localizedTitle,
              detail: scope.localizedDetail
            )
          },
          selectedID: settingsController.state.audioSuggestionScope.rawValue
        ) { value in
          if let scope = AudioSuggestionScope(rawValue: value) {
            settingsController.setAudioSuggestionScope(scope)
          }
        }
      } label: {
        LabeledContent(
          L10n.text("settings.audio.suggestion_scope"),
          value: settingsController.state.audioSuggestionScope.localizedTitle
        )
      }
      .accessibilityHint(L10n.text("settings.audio.suggestion_scope.hint"))

      SettingsLiveAudioInsightSection()

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
          selectedID: settingsController.state.currentFMDXAudioPreset.rawValue
        ) { value in
          if let preset = FMDXAudioTuningPreset(rawValue: value) {
            settingsController.applyFMDXAudioPreset(preset)
          }
        }
      } label: {
        LabeledContent(
          L10n.text("settings.audio.preset"),
          value: settingsController.state.currentFMDXAudioPreset.localizedTitle
        )
      }
      .accessibilityHint(L10n.text("settings.audio.preset.hint"))

      audioSlider(
        title: L10n.text("settings.audio.startup_buffer"),
        value: settingsController.state.fmdxAudioStartupBufferSeconds,
        range: 0.25...1.5,
        step: 0.05,
        hintKey: "settings.audio.startup_buffer.hint"
      ) {
        settingsController.setFMDXAudioStartupBufferSeconds($0)
      }

      audioSlider(
        title: L10n.text("settings.audio.max_latency"),
        value: settingsController.state.fmdxAudioMaxLatencySeconds,
        range: max(0.6, settingsController.state.fmdxAudioStartupBufferSeconds + 0.25)...3.0,
        step: 0.05,
        hintKey: "settings.audio.max_latency.hint"
      ) {
        settingsController.setFMDXAudioMaxLatencySeconds($0)
      }

      audioSlider(
        title: L10n.text("settings.audio.packet_hold"),
        value: settingsController.state.fmdxAudioPacketHoldSeconds,
        range: 0.05...0.35,
        step: 0.01,
        hintKey: "settings.audio.packet_hold.hint"
      ) {
        settingsController.setFMDXAudioPacketHoldSeconds($0)
      }

      FocusRetainingButton {
        settingsController.resetFMDXAudioTuning()
      } label: {
        Text(L10n.text("settings.audio.reset"))
      }
    } header: {
      AppSectionHeader(title: L10n.text("settings.audio.section"))
    } footer: {
      Text(L10n.text("settings.audio.footer"))
    }
    .appSectionStyle()
  }

  private var diagnosticsSection: some View {
    Section {
      NavigationLink {
        DiagnosticsView()
      } label: {
        Label(L10n.text("settings.diagnostics.open"), systemImage: "waveform.path.ecg")
      }
    } header: {
      AppSectionHeader(title: L10n.text("settings.diagnostics.section"))
    }
    .appSectionStyle()
  }

  private var quickActionsSection: some View {
    Section {
      FocusRetainingButton {
        settingsController.reconnectSelectedProfile()
      } label: {
        Text(L10n.text("Reconnect"))
      }
      .disabled(!settingsController.state.canReconnectSelectedProfile)

      FocusRetainingButton {
        settingsController.resetDSPSettings()
      } label: {
        Text(L10n.text("Reset DSP"))
      }
    } header: {
      AppSectionHeader(title: L10n.text("Quick Actions"))
    }
    .appSectionStyle()
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

private struct SettingsLiveAudioInsightSection: View {
  @EnvironmentObject private var settingsController: SettingsViewController

  var body: some View {
    Group {
      if let quality = settingsController.state.audioQualityInsight {
        HStack(spacing: 10) {
          Image(systemName: qualitySymbol(for: quality.level))
            .foregroundStyle(qualityColor(for: quality.level))

          VStack(alignment: .leading, spacing: 2) {
            Text(L10n.text("settings.audio.quality"))
              .font(.subheadline)
            Text(quality.level.localizedTitle)
              .font(.footnote)
              .foregroundStyle(qualityColor(for: quality.level))
          }

          Spacer()

          Text("\(quality.score)/100")
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          L10n.text(
            "settings.audio.quality.accessibility",
            quality.level.localizedTitle,
            quality.score
          )
        )
      } else {
        Text(L10n.text("settings.audio.suggestion.unavailable"))
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      if let suggestion = settingsController.state.audioSuggestionInsight {
        VStack(alignment: .leading, spacing: 6) {
          LabeledContent(
            L10n.text("settings.audio.suggestion"),
            value: suggestion.preset.localizedTitle
          )

          Text(suggestion.localizedReason)
            .font(.footnote)
            .foregroundStyle(.secondary)

          if suggestion.preset != settingsController.state.currentFMDXAudioPreset {
            FocusRetainingButton {
              settingsController.applyFMDXAudioPreset(suggestion.preset)
            } label: {
              Text(L10n.text("settings.audio.suggestion.apply"))
            }
          } else {
            Text(L10n.text("settings.audio.suggestion.current"))
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }
        .accessibilityElement(children: .contain)
      } else if settingsController.state.audioSuggestionScope == .off {
        Text(L10n.text("settings.audio.suggestion.disabled"))
          .font(.footnote)
          .foregroundStyle(.secondary)
      } else {
        Text(L10n.text("settings.audio.suggestion.unavailable"))
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func qualityColor(for level: FMDXAudioQualityLevel) -> Color {
    switch level {
    case .excellent:
      return .green
    case .good:
      return .mint
    case .fair:
      return .yellow
    case .poor:
      return .orange
    case .critical:
      return .red
    }
  }

  private func qualitySymbol(for level: FMDXAudioQualityLevel) -> String {
    switch level {
    case .excellent:
      return "checkmark.circle.fill"
    case .good:
      return "checkmark.circle"
    case .fair:
      return "minus.circle"
    case .poor:
      return "exclamationmark.triangle"
    case .critical:
      return "xmark.octagon.fill"
    }
  }
}
