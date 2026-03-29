import ListenSDRCore
import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var settingsController: SettingsViewController
  @EnvironmentObject private var recordingStore: RecordingStore
  @State private var isCheckingFeedbackServer = false
  @State private var feedbackServerStatus: FeedbackServerStatus = .idle
  @State private var activeAlert: FeedbackServerAlert?
  @State private var isRecordingFolderPickerPresented = false
  @State private var settingsBackupDocument: SettingsBackupDocument?
  @State private var isSettingsBackupExporterPresented = false
  @State private var isSettingsBackupImporterPresented = false

  var body: some View {
    NavigationStack {
      Form {
        startupSection
        connectionSection
        backupRestoreSection
        tuningSection
        scannerSections
        dxSection
      historySection
      radiosSection
      audioSection
      accessibilitySection
      diagnosticsSection
      feedbackSection
      helpSection
      authorSection
      privacyAndFeedbackSection
      }
      .voiceOverStable()
      .scrollContentBackground(.hidden)
      .navigationTitle(L10n.text("Settings"))
      .appScreenBackground()
      .sheet(isPresented: $isRecordingFolderPickerPresented) {
        RecordingFolderPicker(
          onPick: { url in
            recordingStore.setCustomRecordingFolderURL(url)
            isRecordingFolderPickerPresented = false
          },
          onCancel: {
            isRecordingFolderPickerPresented = false
          }
        )
      }
      .fileExporter(
        isPresented: $isSettingsBackupExporterPresented,
        document: settingsBackupDocument,
        contentType: SettingsBackupDocument.readableContentTypes.first ?? .json,
        defaultFilename: settingsController.settingsBackupSuggestedFilename
      ) { result in
        switch result {
        case let .success(url):
          do {
            let data = try SettingsBackupDocument.readData(from: url)
            _ = try RadioSessionSettingsBackupCodec.decodePayload(data)
            activeAlert = FeedbackServerAlert(
              title: L10n.text(
                "settings.backup.export.success.title",
                fallback: "Settings backup saved"
              ),
              message: L10n.text(
                "settings.backup.export.success.body",
                fallback: "The settings backup file was saved successfully."
              )
            )
          } catch {
            activeAlert = FeedbackServerAlert(
              title: L10n.text(
                "settings.backup.export.failure.title",
                fallback: "Unable to save settings backup"
              ),
              message: error.localizedDescription
            )
          }
        case let .failure(error):
          activeAlert = FeedbackServerAlert(
            title: L10n.text(
              "settings.backup.export.failure.title",
              fallback: "Unable to save settings backup"
            ),
            message: error.localizedDescription
          )
        }
      }
      .fileImporter(
        isPresented: $isSettingsBackupImporterPresented,
        allowedContentTypes: SettingsBackupDocument.readableContentTypes,
        allowsMultipleSelection: false
      ) { result in
        switch result {
        case let .success(urls):
          guard let url = urls.first else { return }
          do {
            let data = try SettingsBackupDocument.readData(from: url)
            try settingsController.importSettingsBackup(from: data)
            activeAlert = FeedbackServerAlert(
              title: L10n.text(
                "settings.backup.import.success.title",
                fallback: "Settings backup restored"
              ),
              message: L10n.text(
                "settings.backup.import.success.body",
                fallback: "The selected settings backup file was restored."
              )
            )
          } catch {
            activeAlert = FeedbackServerAlert(
              title: L10n.text(
                "settings.backup.import.failure.title",
                fallback: "Unable to restore settings backup"
              ),
              message: error.localizedDescription
            )
          }
        case let .failure(error):
          activeAlert = FeedbackServerAlert(
            title: L10n.text(
              "settings.backup.import.failure.title",
              fallback: "Unable to restore settings backup"
            ),
            message: error.localizedDescription
          )
        }
      }
      .alert(
        activeAlert?.title ?? "",
        isPresented: Binding(
          get: { activeAlert != nil },
          set: { if !$0 { activeAlert = nil } }
        )
      ) {
        Button(L10n.text("OK")) {
          activeAlert = nil
        }
      } message: {
        Text(activeAlert?.message ?? "")
      }
    }
  }

  private var startupSection: some View {
    Section {
      Toggle(
        L10n.text("settings.session.auto_connect_selected_on_launch"),
        isOn: Binding(
          get: { settingsController.state.autoConnectSelectedProfileOnLaunch },
          set: { settingsController.setAutoConnectSelectedProfileOnLaunch($0) }
        )
      )
      .accessibilityHint(L10n.text("settings.session.auto_connect_selected_on_launch.hint"))

      Toggle(
        L10n.text("settings.session.auto_connect_selected_after_selection"),
        isOn: Binding(
          get: { settingsController.state.autoConnectSelectedProfileAfterSelection },
          set: { settingsController.setAutoConnectSelectedProfileAfterSelection($0) }
        )
      )
      .accessibilityHint(L10n.text("settings.session.auto_connect_selected_after_selection.hint"))
    } header: {
      AppSectionHeader(title: L10n.text("settings.startup.section", fallback: "Startup"))
    }
    .appSectionStyle()
  }

  private var connectionSection: some View {
    Section {
      NavigationLink {
        SelectionListView(
          title: L10n.text("settings.connection.policy.title", fallback: "Allowed network"),
          options: connectionSelectionOptions(),
          selectedID: settingsController.state.connectionNetworkPolicy.rawValue
        ) { value in
          if let policy = ConnectionNetworkPolicy(rawValue: value) {
            settingsController.setConnectionNetworkPolicy(policy)
          }
        }
      } label: {
        LabeledContent(
          L10n.text("settings.connection.policy.title", fallback: "Allowed network"),
          value: settingsController.state.connectionNetworkPolicy.localizedTitle
        )
      }
      .accessibilityHint(
        L10n.text(
          "settings.connection.policy.hint",
          fallback: "Choose whether Listen SDR may connect only on Wi-Fi or also when mobile data is active. Streaming over mobile data can increase usage and charges may apply depending on your plan."
        )
      )
    } header: {
      AppSectionHeader(title: L10n.text("settings.connection.section", fallback: "Connection"))
    }
    .appSectionStyle()
  }

  private var backupRestoreSection: some View {
    Section {
      settingsInfoBlock(
        title: L10n.text("settings.backup_restore.local_point.title", fallback: "Local restore point"),
        description: L10n.text(
          "settings.backup_restore.local_point.description",
          fallback: "Saves one temporary restore point on this device. Use it to return quickly to your earlier settings without creating a file."
        )
      )

      FocusRetainingButton {
        settingsController.saveCurrentSettingsSnapshot()
      } label: {
        Text(L10n.text("settings.backup_restore.local_point.save", fallback: "Save local restore point"))
      }

      FocusRetainingButton {
        settingsController.restoreSavedSettingsSnapshot()
      } label: {
        Text(L10n.text("settings.backup_restore.local_point.restore", fallback: "Restore local restore point"))
      }
      .disabled(!settingsController.state.hasSavedSettingsSnapshot)

      Text(
        settingsController.state.hasSavedSettingsSnapshot
          ? L10n.text("settings.backup_restore.local_point.available", fallback: "A local restore point is available on this device.")
          : L10n.text("settings.backup_restore.local_point.missing", fallback: "No local restore point saved on this device yet.")
      )
      .font(.footnote)
      .foregroundStyle(.secondary)

      settingsInfoBlock(
        title: L10n.text("settings.backup_restore.file.title", fallback: "Backup file"),
        description: L10n.text(
          "settings.backup_restore.file.description",
          fallback: "Creates or restores a settings backup file that you can keep, copy, or move to another device."
        )
      )

      settingsInfoBlock(
        title: L10n.text("settings.backup.scope.title", fallback: "Backup contents"),
        description: L10n.text(
          "settings.backup.scope.description",
          fallback: "Choose which parts of the app should be included in the backup file."
        )
      )

      Toggle(
        L10n.text("settings.backup.scope.app_settings", fallback: "App settings"),
        isOn: Binding(
          get: { settingsController.state.backupIncludesAppSettings },
          set: { settingsController.setBackupIncludesAppSettings($0) }
        )
      )

      Toggle(
        L10n.text("settings.backup.scope.saved_radios", fallback: "Saved radios"),
        isOn: Binding(
          get: { settingsController.state.backupIncludesProfiles },
          set: { settingsController.setBackupIncludesProfiles($0) }
        )
      )

      Toggle(
        L10n.text("settings.backup.scope.saved_radio_passwords", fallback: "Saved radio passwords"),
        isOn: Binding(
          get: { settingsController.state.backupIncludesProfilePasswords },
          set: { settingsController.setBackupIncludesProfilePasswords($0) }
        )
      )
      .disabled(!settingsController.state.backupIncludesProfiles)
      .accessibilityHint(
        L10n.text(
          "settings.backup.scope.saved_radio_passwords.hint",
          fallback: "Available only when saved radios are included in the backup."
        )
      )

      Toggle(
        L10n.text("settings.backup.scope.favorites", fallback: "Favorites"),
        isOn: Binding(
          get: { settingsController.state.backupIncludesFavorites },
          set: { settingsController.setBackupIncludesFavorites($0) }
        )
      )

      Toggle(
        L10n.text("settings.backup.scope.history", fallback: "Listening history"),
        isOn: Binding(
          get: { settingsController.state.backupIncludesHistory },
          set: { settingsController.setBackupIncludesHistory($0) }
        )
      )

      if !isAnyBackupScopeEnabled {
        Text(
          L10n.text(
            "settings.backup.scope.none_selected",
            fallback: "Choose at least one type of data before exporting a backup file."
          )
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }

      FocusRetainingButton {
        do {
          settingsBackupDocument = try settingsController.makeSettingsBackupDocument()
          isSettingsBackupExporterPresented = true
        } catch {
          activeAlert = FeedbackServerAlert(
            title: L10n.text(
              "settings.backup.export.failure.title",
              fallback: "Unable to save settings backup"
            ),
            message: error.localizedDescription
          )
        }
      } label: {
        Text(L10n.text("settings.backup.export", fallback: "Export settings backup"))
      }
      .disabled(!isAnyBackupScopeEnabled)

      FocusRetainingButton {
        isSettingsBackupImporterPresented = true
      } label: {
        Text(L10n.text("settings.backup.import", fallback: "Import settings backup"))
      }

      Text(
        L10n.text(
          "settings.backup.file_hint",
          fallback: "Choose where to save a backup file, or restore settings from an existing backup file."
        )
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
    } header: {
      AppSectionHeader(title: L10n.text("settings.backup_restore.section", fallback: "Backup and restore"))
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

      NavigationLink {
        SelectionListView(
          title: L10n.text(
            "settings.tuning.typed_frequency",
            fallback: "Typed frequency"
          ),
          options: frequencyEntryCommitSelectionOptions(),
          selectedID: settingsController.state.frequencyEntryCommitMode.rawValue
        ) { value in
          if let mode = FrequencyEntryCommitMode(rawValue: value) {
            settingsController.setFrequencyEntryCommitMode(mode)
          }
        }
      } label: {
        LabeledContent(
          L10n.text(
            "settings.tuning.typed_frequency",
            fallback: "Typed frequency"
          ),
          value: settingsController.state.frequencyEntryCommitMode.localizedTitle
        )
      }
      .accessibilityHint(
        L10n.text(
          "settings.tuning.typed_frequency.hint",
          fallback: "Choose whether a typed frequency should tune automatically or wait for manual confirmation."
        )
      )

      Toggle(
        L10n.text("settings.tuning.tune_confirmation_warnings"),
        isOn: Binding(
          get: { settingsController.state.tuneConfirmationWarningsEnabled },
          set: { settingsController.setTuneConfirmationWarningsEnabled($0) }
        )
      )
      .accessibilityHint(L10n.text("settings.tuning.tune_confirmation_warnings.hint"))
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

      NavigationLink {
        SelectionListView(
          title: L10n.text("settings.accessibility.selection_announcements"),
          options: ScreenReaderSelectionAnnouncementMode.allCases.map { mode in
            SelectionListOption(id: mode.rawValue, title: mode.localizedTitle, detail: nil)
          },
          selectedID: settingsController.state.accessibilitySelectionAnnouncementMode.rawValue
        ) { value in
          if let mode = ScreenReaderSelectionAnnouncementMode(rawValue: value) {
            settingsController.setAccessibilitySelectionAnnouncementMode(mode)
          }
        }
      } label: {
        LabeledContent(
          L10n.text("settings.accessibility.selection_announcements"),
          value: settingsController.state.accessibilitySelectionAnnouncementMode.localizedTitle
        )
      }
      .accessibilityHint(L10n.text("settings.accessibility.selection_announcements.hint"))

      Toggle(
        L10n.text("settings.accessibility.interaction_sounds"),
        isOn: Binding(
          get: { settingsController.state.accessibilityInteractionSoundsEnabled },
          set: { settingsController.setAccessibilityInteractionSoundsEnabled($0) }
        )
      )
      .accessibilityHint(L10n.text("settings.accessibility.interaction_sounds.hint"))

      Toggle(
        L10n.text("settings.accessibility.connection_sounds"),
        isOn: Binding(
          get: { settingsController.state.accessibilityConnectionSoundsEnabled },
          set: { settingsController.setAccessibilityConnectionSoundsEnabled($0) }
        )
      )
      .accessibilityHint(L10n.text("settings.accessibility.connection_sounds.hint"))

      Toggle(
        L10n.text("settings.accessibility.recording_sounds"),
        isOn: Binding(
          get: { settingsController.state.accessibilityRecordingSoundsEnabled },
          set: { settingsController.setAccessibilityRecordingSoundsEnabled($0) }
        )
      )
      .accessibilityHint(L10n.text("settings.accessibility.recording_sounds.hint"))

      percentageSlider(
        title: L10n.text("settings.accessibility.interaction_sounds.volume"),
        value: settingsController.state.accessibilityInteractionSoundsVolume,
        range: 0.5...2.5,
        step: 0.05,
        hintKey: "settings.accessibility.interaction_sounds.volume.hint"
      ) {
        settingsController.setAccessibilityInteractionSoundsVolume($0)
      }
      .disabled(!hasAnyAccessibilityFeedbackSoundsEnabled)

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

      Toggle(
        L10n.text("settings.audio.remember_squelch_on_connect"),
        isOn: Binding(
          get: { settingsController.state.rememberSquelchOnConnectEnabled },
          set: { settingsController.setRememberSquelchOnConnectEnabled($0) }
        )
      )
      .accessibilityHint(L10n.text("settings.audio.remember_squelch_on_connect.hint"))

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

      NavigationLink {
        SelectionListView(
          title: L10n.text(
            "settings.audio.speech_loudness_leveling",
            fallback: "Speech loudness leveling"
          ),
          options: speechLoudnessSelectionOptions(),
          selectedID: settingsController.state.accessibilitySpeechLoudnessLevelingMode.rawValue
        ) { value in
          if let mode = SpeechLoudnessLevelingMode(rawValue: value) {
            settingsController.setSpeechLoudnessLevelingMode(mode)
          }
        }
      } label: {
        LabeledContent(
          L10n.text(
            "settings.audio.speech_loudness_leveling",
            fallback: "Speech loudness leveling"
          ),
          value: settingsController.state.accessibilitySpeechLoudnessLevelingMode.localizedTitle
        )
      }
      .accessibilityHint(
        L10n.text(
          "settings.audio.speech_loudness_leveling.hint",
          fallback: "Keeps KiwiSDR and OpenWebRX speech audio closer to one listening level. Recordings and FM-DX playback stay unchanged."
        )
      )

      if settingsController.state.accessibilitySpeechLoudnessLevelingMode == .custom {
        scannerSlider(
          title: L10n.text("settings.audio.speech_loudness_target"),
          value: settingsController.state.accessibilitySpeechLoudnessCustomTargetRMS,
          range: 0.10...0.40,
          step: 0.01,
          valueFormat: "%.2f",
          valueSuffix: "",
          hintKey: "settings.audio.speech_loudness_target.hint"
        ) {
          settingsController.setSpeechLoudnessCustomTargetRMS($0)
        }

        scannerSlider(
          title: L10n.text("settings.audio.speech_loudness_max_gain"),
          value: settingsController.state.accessibilitySpeechLoudnessCustomMaximumGain,
          range: 4.0...24.0,
          step: 0.5,
          valueFormat: "%.1f",
          valueSuffix: "x",
          hintKey: "settings.audio.speech_loudness_max_gain.hint"
        ) {
          settingsController.setSpeechLoudnessCustomMaximumGain($0)
        }

        scannerSlider(
          title: L10n.text("settings.audio.speech_loudness_peak_limit"),
          value: settingsController.state.accessibilitySpeechLoudnessCustomPeakLimit,
          range: 0.70...0.99,
          step: 0.01,
          valueFormat: "%.2f",
          valueSuffix: "",
          hintKey: "settings.audio.speech_loudness_peak_limit.hint"
        ) {
          settingsController.setSpeechLoudnessCustomPeakLimit($0)
        }
      }

      LabeledContent(
        L10n.text(
          "settings.audio.recording_folder",
          fallback: "Recording folder"
        ),
        value: recordingStore.recordingDestinationSummary
      )

      Text(
        L10n.text(
          "settings.audio.recording_folder.hint",
          fallback: "Choose where new recordings are saved. The default location is the app's Recordings folder."
        )
      )
      .font(.footnote)
      .foregroundStyle(.secondary)

      FocusRetainingButton {
        isRecordingFolderPickerPresented = true
      } label: {
        Text(
          L10n.text(
            "settings.audio.recording_folder.choose",
            fallback: "Choose recording folder"
          )
        )
      }
      .disabled(recordingStore.isRecording)

      if recordingStore.hasCustomRecordingDestination {
        FocusRetainingButton {
          recordingStore.resetRecordingFolderToDefault()
        } label: {
          Text(
            L10n.text(
              "settings.audio.recording_folder.reset",
              fallback: "Use default app folder"
            )
          )
        }
        .disabled(recordingStore.isRecording)
      }

      Text(
        L10n.text(
          "settings.audio.recording_folder.providers",
          fallback: "You can choose iCloud Drive, Dropbox, Google Drive, OneDrive, Box, Nextcloud, SMB shares, and other folders exposed in the Files app."
        )
      )
      .font(.footnote)
      .foregroundStyle(.secondary)

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
        Text(L10n.text("settings.diagnostics.open"))
      }

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
      AppSectionHeader(title: L10n.text("settings.diagnostics.section"))
    }
    .appSectionStyle()
  }

  private var feedbackSection: some View {
    Section {
      NavigationLink {
        ListenSDRFeedbackFormView(kind: .bug)
      } label: {
        Text(L10n.text("settings.feedback.report_bug"))
      }

      NavigationLink {
        ListenSDRFeedbackFormView(kind: .suggestion)
      } label: {
        Text(L10n.text("settings.feedback.send_suggestion"))
      }

      FocusRetainingButton {
        startFeedbackServerHealthCheck()
      } label: {
        Text(
          isCheckingFeedbackServer
            ? L10n.text("settings.feedback.health_check.checking")
            : L10n.text("settings.feedback.health_check")
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

  private var privacyAndFeedbackSection: some View {
    Section {
      settingsInfoBlock(
        title: L10n.text(
          "settings.privacy_feedback.privacy_title",
          fallback: "Your data stays under your control"
        ),
        description: L10n.text(
          "settings.privacy_feedback.privacy_body",
          fallback: "Listen SDR does not send diagnostics, listening history, or receiver data without your action. When you choose to send a bug report or suggestion, only the information you review and confirm is sent."
        )
      )

      settingsInfoBlock(
        title: L10n.text(
          "settings.privacy_feedback.feedback_title",
          fallback: "Feedback helps improve the app"
        ),
        description: L10n.text(
          "settings.privacy_feedback.feedback_body",
          fallback: "Bug reports and suggestions help improve stability, accessibility, and receiver support. If something is wrong or missing, please use the feedback options above."
        )
      )
    } header: {
      AppSectionHeader(title: L10n.text("settings.privacy_feedback.section", fallback: "Privacy and feedback"))
    }
    .appSectionStyle()
  }

  private var helpSection: some View {
    Section {
      NavigationLink {
        AppTutorialView(isPresentedOnLaunch: false)
      } label: {
        Text(L10n.text("tutorial.navigation_title", fallback: "Tutorial"))
      }

      Toggle(
        L10n.text(
          "tutorial.show_on_launch.title",
          fallback: "Show this tutorial on app start"
        ),
        isOn: Binding(
          get: { settingsController.state.showTutorialOnLaunchEnabled },
          set: { settingsController.setShowTutorialOnLaunchEnabled($0) }
        )
      )
      .accessibilityHint(
        L10n.text(
          "tutorial.show_on_launch.hint",
          fallback: "Turn this off if you do not want the tutorial to open automatically next time."
        )
      )
    } header: {
      AppSectionHeader(title: L10n.text("settings.help.section", fallback: "Help"))
    }
    .appSectionStyle()
  }

  private func settingsInfoBlock(title: String, description: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.headline)

      Text(description)
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
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

  private func frequencyEntryCommitSelectionOptions() -> [SelectionListOption] {
    FrequencyEntryCommitMode.allCases.map { mode in
      SelectionListOption(
        id: mode.rawValue,
        title: mode.localizedTitle,
        detail: mode.localizedDetail
      )
    }
  }

  private func speechLoudnessSelectionOptions() -> [SelectionListOption] {
    SpeechLoudnessLevelingMode.allCases.map { mode in
      SelectionListOption(
        id: mode.rawValue,
        title: mode.localizedTitle,
        detail: mode.localizedDetail
      )
    }
  }

  private func connectionSelectionOptions() -> [SelectionListOption] {
    ConnectionNetworkPolicy.allCases.map { policy in
      SelectionListOption(
        id: policy.rawValue,
        title: policy.localizedTitle,
        detail: policy.localizedDetail
      )
    }
  }

  private func scannerSlider(
    title: String,
    value: Double,
    range: ClosedRange<Double>,
    step: Double,
    valueFormat: String = "%.1f",
    valueSuffix: String = " s",
    hintKey: String? = nil,
    onChange: @escaping (Double) -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      LabeledContent(
        title,
        value: "\(String(format: valueFormat, value))\(valueSuffix)"
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
        value: "\(String(format: valueFormat, value))\(valueSuffix)",
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

  private var hasAnyAccessibilityFeedbackSoundsEnabled: Bool {
    settingsController.state.accessibilityInteractionSoundsEnabled
      || settingsController.state.accessibilityConnectionSoundsEnabled
      || settingsController.state.accessibilityRecordingSoundsEnabled
  }

  private var isAnyBackupScopeEnabled: Bool {
    settingsController.state.backupIncludesAppSettings
      || settingsController.state.backupIncludesProfiles
      || settingsController.state.backupIncludesFavorites
      || settingsController.state.backupIncludesHistory
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
            activeAlert = FeedbackServerAlert(
              title: L10n.text("settings.feedback.health_check.success.title"),
              message: L10n.text("settings.feedback.health_check.success.body")
            )
          } else {
            feedbackServerStatus = .failure
            activeAlert = FeedbackServerAlert(
              title: L10n.text("settings.feedback.health_check.failure.title"),
              message: L10n.text("settings.feedback.health_check.failure.body")
            )
          }
        }
      } catch {
        await MainActor.run {
          isCheckingFeedbackServer = false
          feedbackServerStatus = .failure
          activeAlert = FeedbackServerAlert(
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
