import ListenSDRCore
import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var settingsController: SettingsViewController
  @State private var isCheckingFeedbackServer = false
  @State private var feedbackServerStatus: FeedbackServerStatus = .idle
  @State private var feedbackServerAlert: FeedbackServerAlert?

  var body: some View {
    NavigationStack {
      Form {
        sessionSection
        tuningSection
        scannerSections
        dxSection
        historySection
        radiosSection
        audioSection
        accessibilitySection
        diagnosticsSection
        feedbackSection
        quickActionsSection
        authorSection
      }
      .voiceOverStable()
      .scrollContentBackground(.hidden)
      .navigationTitle(L10n.text("Settings"))
      .appScreenBackground()
      .alert(
        feedbackServerAlert?.title ?? "",
        isPresented: Binding(
          get: { feedbackServerAlert != nil },
          set: { if !$0 { feedbackServerAlert = nil } }
        )
      ) {
        Button(L10n.text("OK")) {
          feedbackServerAlert = nil
        }
      } message: {
        Text(feedbackServerAlert?.message ?? "")
      }
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

      Toggle(
        L10n.text("settings.session.auto_connect_selected_on_launch"),
        isOn: Binding(
          get: { settingsController.state.autoConnectSelectedProfileOnLaunch },
          set: { settingsController.setAutoConnectSelectedProfileOnLaunch($0) }
        )
      )
      .accessibilityHint(L10n.text("settings.session.auto_connect_selected_on_launch.hint"))
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
          options: tuneStepSelectionOptions(),
          selectedID: tuneStepSelectionID
        ) { value in
          if value == TuneStepPreferenceMode.automatic.rawValue {
            settingsController.setTuneStepPreferenceMode(.automatic)
          } else if let stepHz = Int(value) {
            settingsController.setTuneStepHz(stepHz)
          }
        }
      } label: {
        LabeledContent(
          L10n.text("settings.tuning.global_step"),
          value: tuneStepSummaryValue
        )
      }
      .accessibilityHint(L10n.text("settings.tuning.global_step.hint"))

      Toggle(
        L10n.text("settings.tuning.fmdx_tune_confirmation_warnings"),
        isOn: Binding(
          get: { settingsController.state.fmdxTuneConfirmationWarningsEnabled },
          set: { settingsController.setFMDXTuneConfirmationWarningsEnabled($0) }
        )
      )
      .accessibilityHint(L10n.text("settings.tuning.fmdx_tune_confirmation_warnings.hint"))
    } header: {
      AppSectionHeader(title: L10n.text("settings.tuning.section"))
    }
    .appSectionStyle()
  }

  private var accessibilitySection: some View {
    Section {
      NavigationLink {
        SelectionListView(
          title: L10n.text("settings.accessibility.magic_tap"),
          options: MagicTapAction.allCases.map { action in
            SelectionListOption(
              id: action.rawValue,
              title: action.localizedTitle,
              detail: action.localizedDetail
            )
          },
          selectedID: settingsController.state.magicTapAction.rawValue
        ) { value in
          if let action = MagicTapAction(rawValue: value) {
            settingsController.setMagicTapAction(action)
          }
        }
      } label: {
        LabeledContent(
          L10n.text("settings.accessibility.magic_tap"),
          value: settingsController.state.magicTapAction.localizedTitle
        )
      }
      .accessibilityHint(L10n.text("settings.accessibility.magic_tap.hint"))

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

      Toggle(
        L10n.text("settings.accessibility.interaction_sounds"),
        isOn: Binding(
          get: { settingsController.state.accessibilityInteractionSoundsEnabled },
          set: { settingsController.setAccessibilityInteractionSoundsEnabled($0) }
        )
      )
      .accessibilityHint(L10n.text("settings.accessibility.interaction_sounds.hint"))

      percentageSlider(
        title: L10n.text("settings.accessibility.interaction_sounds.volume"),
        value: settingsController.state.accessibilityInteractionSoundsVolume,
        range: 0.5...2.5,
        step: 0.05,
        hintKey: "settings.accessibility.interaction_sounds.volume.hint"
      ) {
        settingsController.setAccessibilityInteractionSoundsVolume($0)
      }
      .disabled(!settingsController.state.accessibilityInteractionSoundsEnabled)

      FocusRetainingButton {
        AppInteractionFeedbackCenter.playInteractionSoundPreviewIfEnabled()
      } label: {
        Text(L10n.text("settings.accessibility.interaction_sounds.preview"))
      }
      .disabled(!settingsController.state.accessibilityInteractionSoundsEnabled)
      .accessibilityHint(L10n.text("settings.accessibility.interaction_sounds.preview.hint"))

      Toggle(
        L10n.text("settings.accessibility.interaction_sounds.mute_while_recording"),
        isOn: Binding(
          get: { settingsController.state.accessibilityInteractionSoundsMutedDuringRecording },
          set: { settingsController.setAccessibilityInteractionSoundsMutedDuringRecording($0) }
        )
      )
      .disabled(!settingsController.state.accessibilityInteractionSoundsEnabled)
      .accessibilityHint(L10n.text("settings.accessibility.interaction_sounds.mute_while_recording.hint"))
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

      Toggle(
        L10n.text("settings.history.show_recent_frequencies"),
        isOn: Binding(
          get: { settingsController.state.showRecentFrequencies },
          set: { settingsController.setShowRecentFrequencies($0) }
        )
      )
      .accessibilityHint(L10n.text("settings.history.show_recent_frequencies.hint"))

      Toggle(
        L10n.text("settings.history.include_other_receivers"),
        isOn: Binding(
          get: { settingsController.state.includeRecentFrequenciesFromOtherReceivers },
          set: { settingsController.setIncludeRecentFrequenciesFromOtherReceivers($0) }
        )
      )
      .disabled(!settingsController.state.showRecentFrequencies)
      .accessibilityHint(L10n.text("settings.history.include_other_receivers.hint"))
    } header: {
      AppSectionHeader(title: L10n.text("settings.history.section"))
    }
    .appSectionStyle()
  }

  private var radiosSection: some View {
    Section {
      NavigationLink {
        SelectionListView(
          title: L10n.text("settings.radios.search_filters"),
          options: RadiosSearchFiltersVisibility.allCases.map { visibility in
            SelectionListOption(
              id: visibility.rawValue,
              title: visibility.localizedTitle,
              detail: visibility.localizedDetail
            )
          },
          selectedID: settingsController.state.radiosSearchFiltersVisibility.rawValue
        ) { value in
          if let visibility = RadiosSearchFiltersVisibility(rawValue: value) {
            settingsController.setRadiosSearchFiltersVisibility(visibility)
          }
        }
      } label: {
        LabeledContent(
          L10n.text("settings.radios.search_filters"),
          value: settingsController.state.radiosSearchFiltersVisibility.localizedTitle
        )
      }
      .accessibilityHint(L10n.text("settings.radios.search_filters.hint"))
    } header: {
      AppSectionHeader(title: L10n.text("settings.radios.section"))
    }
    .appSectionStyle()
  }

  @ViewBuilder
  private var scannerSections: some View {
    Section {
      Toggle(
        L10n.text("settings.scanner.channel_adaptive"),
        isOn: Binding(
          get: { settingsController.state.adaptiveScannerEnabled },
          set: { settingsController.setAdaptiveScannerEnabled($0) }
        )
      )
      .accessibilityHint(L10n.text("settings.scanner.channel_adaptive.hint"))

      scannerSlider(
        title: L10n.text("settings.scanner.dwell"),
        value: settingsController.state.scannerDwellSeconds,
        range: 0.5...6,
        step: 0.1
      ) {
        settingsController.setScannerDwellSeconds($0)
      }

      scannerSlider(
        title: L10n.text("settings.scanner.hold"),
        value: settingsController.state.scannerHoldSeconds,
        range: 0.5...12,
        step: 0.1
      ) {
        settingsController.setScannerHoldSeconds($0)
      }

      Toggle(
        L10n.text("settings.scanner.play_detected_signals"),
        isOn: Binding(
          get: { settingsController.state.playDetectedChannelScannerSignalsEnabled },
          set: { settingsController.setPlayDetectedChannelScannerSignalsEnabled($0) }
        )
      )
      .accessibilityHint(L10n.text("settings.scanner.play_detected_signals.hint"))

      Toggle(
        L10n.text("settings.scanner.save_channel_results"),
        isOn: Binding(
          get: { settingsController.state.saveChannelScannerResultsEnabled },
          set: { settingsController.setSaveChannelScannerResultsEnabled($0) }
        )
      )
      .accessibilityHint(L10n.text("settings.scanner.save_channel_results.hint"))

      Toggle(
        L10n.text("settings.scanner.stop_channel_on_signal"),
        isOn: Binding(
          get: { settingsController.state.stopChannelScannerOnSignal },
          set: { settingsController.setStopChannelScannerOnSignal($0) }
        )
      )
      .accessibilityHint(L10n.text("settings.scanner.stop_channel_on_signal.hint"))

      Toggle(
        L10n.text("settings.scanner.filter_interference"),
        isOn: Binding(
          get: { settingsController.state.filterChannelScannerInterferenceEnabled },
          set: { settingsController.setFilterChannelScannerInterferenceEnabled($0) }
        )
      )
      .accessibilityHint(L10n.text("settings.scanner.filter_interference.hint"))

      NavigationLink {
        SelectionListView(
          title: L10n.text("settings.scanner.interference_profile"),
          options: ChannelScannerInterferenceFilterProfile.allCases.map { profile in
            SelectionListOption(
              id: profile.rawValue,
              title: profile.localizedTitle,
              detail: profile.localizedDetail
            )
          },
          selectedID: settingsController.state.channelScannerInterferenceFilterProfile.rawValue
        ) { value in
          if let profile = ChannelScannerInterferenceFilterProfile(rawValue: value) {
            settingsController.setChannelScannerInterferenceFilterProfile(profile)
          }
        }
      } label: {
        LabeledContent(
          L10n.text("settings.scanner.interference_profile"),
          value: settingsController.state.channelScannerInterferenceFilterProfile.localizedTitle
        )
      }
      .disabled(!settingsController.state.filterChannelScannerInterferenceEnabled)
      .accessibilityHint(L10n.text("settings.scanner.interference_profile.hint"))
    } header: {
      AppSectionHeader(title: L10n.text("settings.scanner.channel_section"))
    }
    .appSectionStyle()

    Section {
      Toggle(
        L10n.text("settings.scanner.save_fmdx_results"),
        isOn: Binding(
          get: { settingsController.state.saveFMDXScannerResultsEnabled },
          set: { settingsController.setSaveFMDXScannerResultsEnabled($0) }
        )
      )
      .accessibilityHint(L10n.text("settings.scanner.save_fmdx_results.hint"))

      NavigationLink {
        SelectionListView(
          title: L10n.text("settings.scanner.fmdx_start_behavior"),
          options: FMDXBandScanStartBehavior.allCases.map { behavior in
            SelectionListOption(id: behavior.rawValue, title: behavior.localizedTitle, detail: nil)
          },
          selectedID: settingsController.state.fmdxBandScanStartBehavior.rawValue
        ) { value in
          if let behavior = FMDXBandScanStartBehavior(rawValue: value) {
            settingsController.setFMDXBandScanStartBehavior(behavior)
          }
        }
      } label: {
        LabeledContent(
          L10n.text("settings.scanner.fmdx_start_behavior"),
          value: settingsController.state.fmdxBandScanStartBehavior.localizedTitle
        )
      }
      .accessibilityHint(L10n.text("settings.scanner.fmdx_start_behavior.hint"))

      NavigationLink {
        SelectionListView(
          title: L10n.text("settings.scanner.fmdx_hit_behavior"),
          options: FMDXBandScanHitBehavior.allCases.map { behavior in
            SelectionListOption(id: behavior.rawValue, title: behavior.localizedTitle, detail: nil)
          },
          selectedID: settingsController.state.fmdxBandScanHitBehavior.rawValue
        ) { value in
          if let behavior = FMDXBandScanHitBehavior(rawValue: value) {
            settingsController.setFMDXBandScanHitBehavior(behavior)
          }
        }
      } label: {
        LabeledContent(
          L10n.text("settings.scanner.fmdx_hit_behavior"),
          value: settingsController.state.fmdxBandScanHitBehavior.localizedTitle
        )
      }
      .accessibilityHint(L10n.text("settings.scanner.fmdx_hit_behavior.hint"))

      Text(L10n.text("settings.scanner.fmdx_custom_info"))
        .font(.footnote)
        .foregroundStyle(.secondary)

      scannerSlider(
        title: L10n.text("settings.scanner.fmdx_custom_settle"),
        value: settingsController.state.fmdxCustomScanSettleSeconds,
        range: 0.05...0.60,
        step: 0.01,
        valueFormat: "%.2f",
        hintKey: "settings.scanner.fmdx_custom_settle.hint"
      ) {
        settingsController.setFMDXCustomScanSettleSeconds($0)
      }

      scannerSlider(
        title: L10n.text("settings.scanner.fmdx_custom_metadata_window"),
        value: settingsController.state.fmdxCustomScanMetadataWindowSeconds,
        range: 0.0...2.0,
        step: 0.05,
        valueFormat: "%.2f",
        hintKey: "settings.scanner.fmdx_custom_metadata_window.hint"
      ) {
        settingsController.setFMDXCustomScanMetadataWindowSeconds($0)
      }
    } header: {
      AppSectionHeader(title: L10n.text("settings.scanner.fmdx_section"))
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

      Toggle(
        L10n.text("settings.audio.mix_with_other_apps"),
        isOn: Binding(
          get: { settingsController.state.mixWithOtherAudioApps },
          set: { settingsController.setMixWithOtherAudioApps($0) }
        )
      )
      .accessibilityHint(L10n.text("settings.audio.mix_with_other_apps.hint"))

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

  private var feedbackSection: some View {
    Section {
      NavigationLink {
        ListenSDRFeedbackFormView(kind: .bug)
      } label: {
        Label(L10n.text("settings.feedback.report_bug"), systemImage: "ant.circle")
      }

      NavigationLink {
        ListenSDRFeedbackFormView(kind: .suggestion)
      } label: {
        Label(L10n.text("settings.feedback.send_suggestion"), systemImage: "lightbulb")
      }

      FocusRetainingButton {
        startFeedbackServerHealthCheck()
      } label: {
        Label(
          isCheckingFeedbackServer
            ? L10n.text("settings.feedback.health_check.checking")
            : L10n.text("settings.feedback.health_check"),
          systemImage: "network"
        )
      }
      .disabled(isCheckingFeedbackServer)
      .accessibilityHint(L10n.text("settings.feedback.health_check.hint"))

      if feedbackServerStatus != .idle {
        LabeledContent(
          L10n.text("settings.feedback.health_check.status"),
          value: feedbackServerStatus.localizedTitle
        )
        .font(.footnote)
      }
    } header: {
      AppSectionHeader(title: L10n.text("settings.feedback.section"))
    }
    .appSectionStyle()
  }

  private var authorSection: some View {
    Section {
      Text("Kazek5p")
    } header: {
      AppSectionHeader(title: L10n.text("settings.author.section"))
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
      .accessibilityHidden(true)

      Slider(
        value: Binding(
          get: { value },
          set: { onChange($0) }
        ),
        in: range,
        step: step
      )
      .accessibleControl(
        label: title,
        value: "\(String(format: "%.2f", value)) s",
        hint: L10n.text(hintKey)
      )
    }
  }

  private var tuneStepSelectionID: String {
    settingsController.state.tuneStepPreferenceMode == .automatic
      ? TuneStepPreferenceMode.automatic.rawValue
      : "\(settingsController.state.tuneStepHz)"
  }

  private var tuneStepSummaryValue: String {
    switch settingsController.state.tuneStepPreferenceMode {
    case .manual:
      return FrequencyFormatter.tuneStepText(fromHz: settingsController.state.tuneStepHz)
    case .automatic:
      return settingsController.state.tuneStepPreferenceMode.localizedTitle
    }
  }

  private func tuneStepSelectionOptions() -> [SelectionListOption] {
    let automaticOption = SelectionListOption(
      id: TuneStepPreferenceMode.automatic.rawValue,
      title: TuneStepPreferenceMode.automatic.localizedTitle,
      detail: TuneStepPreferenceMode.automatic.localizedDetail
    )

    let manualOptions = settingsController.state.tuneStepOptions.map { stepHz in
      SelectionListOption(
        id: "\(stepHz)",
        title: FrequencyFormatter.tuneStepText(fromHz: stepHz),
        detail: nil
      )
    }

    return [automaticOption] + manualOptions
  }

  private func scannerSlider(
    title: String,
    value: Double,
    range: ClosedRange<Double>,
    step: Double,
    valueFormat: String = "%.1f",
    hintKey: String? = nil,
    onChange: @escaping (Double) -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      LabeledContent(
        title,
        value: "\(String(format: valueFormat, value)) s"
      )
      .accessibilityHidden(true)

      Slider(
        value: Binding(
          get: { value },
          set: { onChange($0) }
        ),
        in: range,
        step: step
      )
      .accessibleControl(
        label: title,
        value: "\(String(format: valueFormat, value)) s",
        hint: hintKey.map { L10n.text($0) }
      )
    }
  }

  private func percentageSlider(
    title: String,
    value: Double,
    range: ClosedRange<Double>,
    step: Double,
    hintKey: String,
    onChange: @escaping (Double) -> Void
  ) -> some View {
    let percentageValue = Int((value * 100).rounded())
    return VStack(alignment: .leading, spacing: 6) {
      LabeledContent(
        title,
        value: "\(percentageValue)%"
      )
      .accessibilityHidden(true)

      Slider(
        value: Binding(
          get: { value },
          set: { onChange($0) }
        ),
        in: range,
        step: step
      )
      .accessibleControl(
        label: title,
        value: "\(percentageValue)%",
        hint: L10n.text(hintKey)
      )
    }
  }

  private func startFeedbackServerHealthCheck() {
    guard !isCheckingFeedbackServer else { return }

    isCheckingFeedbackServer = true
    feedbackServerStatus = .checking

    Task {
      do {
        let isHealthy = try await ListenSDRFeedbackSender.checkHealth()
        await MainActor.run {
          isCheckingFeedbackServer = false
          if isHealthy {
            feedbackServerStatus = .success
            feedbackServerAlert = FeedbackServerAlert(
              title: L10n.text("settings.feedback.health_check.success.title"),
              message: L10n.text("settings.feedback.health_check.success.body")
            )
          } else {
            feedbackServerStatus = .failure
            feedbackServerAlert = FeedbackServerAlert(
              title: L10n.text("settings.feedback.health_check.failure.title"),
              message: L10n.text("settings.feedback.health_check.failure.body")
            )
          }
        }
      } catch {
        await MainActor.run {
          isCheckingFeedbackServer = false
          feedbackServerStatus = .failure
          feedbackServerAlert = FeedbackServerAlert(
            title: L10n.text("settings.feedback.health_check.failure.title"),
            message: L10n.text("settings.feedback.health_check.failure.body")
          )
        }
      }
    }
  }
}

private struct FeedbackServerAlert: Identifiable {
  let id = UUID()
  let title: String
  let message: String
}

private enum FeedbackServerStatus: Equatable {
  case idle
  case checking
  case success
  case failure

  var localizedTitle: String {
    switch self {
    case .idle:
      return ""
    case .checking:
      return L10n.text("settings.feedback.health_check.checking")
    case .success:
      return L10n.text("settings.feedback.health_check.status.success")
    case .failure:
      return L10n.text("settings.feedback.health_check.status.failure")
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
