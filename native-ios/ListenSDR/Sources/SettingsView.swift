import ListenSDRCore
import SwiftUI
import UIKit

struct SettingsView: View {
  @AppStorage(AppTheme.selectionKey) private var selectedThemeID = AppThemeOption.classic.rawValue
  @EnvironmentObject private var settingsController: SettingsViewController
  @EnvironmentObject private var recordingStore: RecordingStore
  @State private var isCheckingFeedbackServer = false
  @State private var feedbackServerStatus: FeedbackServerStatus = .idle
  @State private var activeAlert: FeedbackServerAlert?
  @State private var inlineStatus: SettingsInlineStatus?
  @State private var isRecordingFolderPickerPresented = false
  @State private var settingsBackupDocument: SettingsBackupDocument?
  @State private var isSettingsBackupExporterPresented = false
  @State private var isSettingsBackupImporterPresented = false
  @State private var customThemeImportPayload = ""
  @State private var isCustomThemeImportSheetPresented = false
  @State private var pendingFocusRestoreTarget: SettingsFocusTarget?
  @AccessibilityFocusState private var focusedSettingsControl: SettingsFocusTarget?

  var body: some View {
    NavigationStack {
      settingsRootList
      .voiceOverStable()
      .scrollContentBackground(.hidden)
      .navigationTitle(L10n.text("Settings"))
      .appScreenBackground()
      .foregroundStyle(AppTheme.primaryText)
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
      .sheet(isPresented: $isCustomThemeImportSheetPresented) {
        NavigationStack {
          VStack(alignment: .leading, spacing: 12) {
            Text(
              L10n.text(
                "settings.appearance.custom.import.description",
                fallback: "Paste a custom skin JSON export here. Importing replaces your current custom colors."
              )
            )
            .font(.footnote)
            .foregroundStyle(AppTheme.secondaryText)

            TextEditor(text: $customThemeImportPayload)
              .frame(minHeight: 220)
              .padding(8)
              .background(AppTheme.cardFill)
              .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                  .stroke(AppTheme.cardStroke, lineWidth: 1)
              }

            HStack(spacing: 12) {
              FocusRetainingButton {
                customThemeImportPayload = UIPasteboard.general.string ?? ""
              } label: {
                Text(
                  L10n.text(
                    "settings.appearance.custom.import.load_clipboard",
                    fallback: "Load clipboard"
                  )
                )
              }

              FocusRetainingButton {
                applyImportedCustomTheme(customThemeImportPayload)
              } label: {
                Text(
                  L10n.text(
                    "settings.appearance.custom.import.apply",
                    fallback: "Import custom skin"
                  )
                )
              }
            }

            Spacer()
          }
          .padding()
          .navigationTitle(
            L10n.text(
              "settings.appearance.custom.import.sheet_title",
              fallback: "Import custom skin"
            )
          )
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button(L10n.text("Cancel")) {
                isCustomThemeImportSheetPresented = false
              }
            }
          }
          .appScreenBackground()
        }
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
            presentInlineStatus(
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
            presentInlineStatus(
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
      .onChange(of: isRecordingFolderPickerPresented) { isPresented in
        if !isPresented {
          restoreFocusIfNeeded(for: .recordingFolder)
        }
      }
      .onChange(of: isCustomThemeImportSheetPresented) { isPresented in
        if !isPresented {
          restoreFocusIfNeeded(for: .customThemeImport)
        }
      }
      .onChange(of: isSettingsBackupExporterPresented) { isPresented in
        if !isPresented {
          restoreFocusIfNeeded(for: .settingsExport)
        }
      }
      .onChange(of: isSettingsBackupImporterPresented) { isPresented in
        if !isPresented {
          restoreFocusIfNeeded(for: .settingsImport)
        }
      }
    }
  }

  private func selectionAnnouncement(title _: String) -> (SelectionListOption) -> String? {
    { option in
      AppAccessibilityAnnouncementCenter.selectionAnnouncementText(
        title: "",
        value: option.title,
        includeTitle: false
      )
    }
  }

  private var settingsRootList: some View {
    Form {
      settingsStatusSection

      NavigationLink {
        settingsDestinationScreen(
          title: L10n.text(
            "settings.group.startup_connection",
            fallback: "Startup and connection"
          )
        ) {
          startupSection
          connectionSection
        }
      } label: {
        settingsRowLabel(
          title: L10n.text(
            "settings.group.startup_connection",
            fallback: "Startup and connection"
          ),
          summary: startupConnectionSummary
        )
      }

      NavigationLink {
        settingsDestinationScreen(
          title: L10n.text(
            "settings.group.tuning_scanning",
            fallback: "Tuning and scanning"
          )
        ) {
          tuningSection
          scannerSections
          dxSection
        }
      } label: {
        settingsRowLabel(
          title: L10n.text(
            "settings.group.tuning_scanning",
            fallback: "Tuning and scanning"
          ),
          summary: tuningScanningSummary
        )
      }

      NavigationLink {
        settingsDestinationScreen(
          title: L10n.text(
            "settings.group.history_radios",
            fallback: "History and radios"
          )
        ) {
          historySection
          radiosSection
        }
      } label: {
        settingsRowLabel(
          title: L10n.text(
            "settings.group.history_radios",
            fallback: "History and radios"
          ),
          summary: historyRadiosSummary
        )
      }

      NavigationLink {
        settingsDestinationScreen(
          title: L10n.text("settings.audio.section")
        ) {
          audioSections
        }
      } label: {
        settingsRowLabel(
          title: L10n.text("settings.audio.section"),
          summary: audioSettingsSummary
        )
      }

      NavigationLink {
        settingsDestinationScreen(
          title: L10n.text("settings.appearance.section", fallback: "Appearance")
        ) {
          appearanceSection
        }
      } label: {
        settingsRowLabel(
          title: L10n.text("settings.appearance.section", fallback: "Appearance"),
          summary: appearanceSettingsSummary
        )
      }

      NavigationLink {
        settingsDestinationScreen(
          title: L10n.text("settings.accessibility.section")
        ) {
          accessibilitySections
        }
      } label: {
        settingsRowLabel(
          title: L10n.text("settings.accessibility.section"),
          summary: accessibilitySettingsSummary
        )
      }

      NavigationLink {
        settingsDestinationScreen(
          title: L10n.text("settings.backup_restore.section", fallback: "Backup and restore")
        ) {
          backupRestoreSections
        }
      } label: {
        settingsRowLabel(
          title: L10n.text("settings.backup_restore.section", fallback: "Backup and restore"),
          summary: backupRestoreSummary
        )
      }

      NavigationLink {
        settingsDestinationScreen(
          title: L10n.text(
            "settings.group.diagnostics_feedback",
            fallback: "Diagnostics and feedback"
          )
        ) {
          diagnosticsSection
          feedbackSection
        }
      } label: {
        settingsRowLabel(
          title: L10n.text(
            "settings.group.diagnostics_feedback",
            fallback: "Diagnostics and feedback"
          ),
          summary: diagnosticsFeedbackSummary
        )
      }

      NavigationLink {
        settingsDestinationScreen(
          title: L10n.text(
            "settings.group.help_privacy",
            fallback: "Help and privacy"
          )
        ) {
          helpSection
          supportSection
          authorSection
          privacyAndFeedbackSection
        }
      } label: {
        settingsRowLabel(
          title: L10n.text(
            "settings.group.help_privacy",
            fallback: "Help and privacy"
          ),
          summary: helpPrivacySummary
        )
      }
    }
  }

  private func settingsDestinationScreen<Content: View>(
    title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    Form {
      settingsStatusSection
      content()
    }
    .voiceOverStable()
    .scrollContentBackground(.hidden)
    .navigationTitle(title)
    .appScreenBackground()
    .foregroundStyle(AppTheme.primaryText)
    .id(selectedThemeID)
  }

  private var appearanceSection: some View {
    Section {
      Text(
        L10n.text(
          "settings.appearance.theme.description",
          fallback: "Choose the visual skin that feels best to you. This only changes the look and colors, not the layout or workflow."
        )
      )
      .font(.footnote)
      .foregroundStyle(AppTheme.secondaryText)

      NavigationLink {
        SelectionListView(
          title: L10n.text("settings.appearance.theme.title", fallback: "Color theme"),
          options: appearanceThemeOptions(),
          selectedID: selectedThemeID,
          selectionAnnouncement: selectionAnnouncement(
            title: L10n.text("settings.appearance.theme.title", fallback: "Color theme")
          )
        ) { value in
          if AppThemeOption(rawValue: value) != nil {
            selectedThemeID = value
          }
        }
      } label: {
        LabeledContent(
          L10n.text("settings.appearance.theme.title", fallback: "Color theme"),
          value: selectedThemeTitle
        )
      }

      Text(selectedThemeDetail)
        .font(.footnote)
        .foregroundStyle(AppTheme.secondaryText)

      NavigationLink {
        CustomThemeEditorView()
      } label: {
        LabeledContent(
          L10n.text(
            "settings.appearance.custom.navigation_title",
            fallback: "Customize skin"
          ),
          value: L10n.text(
            "settings.appearance.theme.custom",
            fallback: "Custom"
          )
        )
      }
    }
    .appSectionStyle()
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
          selectedID: settingsController.state.connectionNetworkPolicy.rawValue,
          selectionAnnouncement: selectionAnnouncement(
            title: L10n.text("settings.connection.policy.title", fallback: "Allowed network")
          )
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

  @ViewBuilder
  private var backupRestoreSections: some View {
    Section {
      settingsSectionDescription(
        L10n.text(
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
    } header: {
      AppSectionHeader(
        title: L10n.text("settings.backup_restore.local_point.title", fallback: "Local restore point")
      )
    }
    .appSectionStyle()

    Section {
      settingsSectionDescription(
        L10n.text(
          "settings.backup_restore.custom_skin.description",
          fallback: "Copy, share, or import the JSON for your own skin. This only affects the custom skin colors, not the rest of the app settings."
        )
      )

      FocusRetainingButton {
        copyCustomThemeToClipboard()
      } label: {
        Text(
          L10n.text(
            "settings.appearance.custom.export.copy",
            fallback: "Copy custom skin JSON"
          )
        )
      }

      if let exportPayload = try? AppTheme.exportCustomThemeJSONString() {
        ShareLink(
          item: exportPayload,
          preview: SharePreview(
            L10n.text(
              "settings.appearance.custom.export.share_title",
              fallback: "Listen SDR custom skin"
            )
          )
        ) {
          Text(
            L10n.text(
              "settings.appearance.custom.export.share",
              fallback: "Share custom skin JSON"
            )
          )
        }
      }

      FocusRetainingButton {
        importCustomThemeFromClipboard()
      } label: {
        Text(
          L10n.text(
            "settings.appearance.custom.import.clipboard",
            fallback: "Import custom skin from clipboard"
          )
        )
      }

      Button {
        pendingFocusRestoreTarget = .customThemeImport
        customThemeImportPayload = UIPasteboard.general.string ?? ""
        isCustomThemeImportSheetPresented = true
      } label: {
        Text(
          L10n.text(
            "settings.appearance.custom.import.manual",
            fallback: "Paste custom skin JSON"
          )
        )
      }
      .accessibilityFocused($focusedSettingsControl, equals: .customThemeImport)
    } header: {
      AppSectionHeader(
        title: L10n.text("settings.backup_restore.custom_skin.title", fallback: "Custom skin")
      )
    }
    .appSectionStyle()

    Section {
      settingsSectionDescription(
        L10n.text(
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
    } header: {
      AppSectionHeader(title: L10n.text("settings.backup.scope.title", fallback: "Backup contents"))
    }
    .appSectionStyle()

    Section {
      settingsSectionDescription(
        L10n.text(
          "settings.backup_restore.file.description",
          fallback: "Creates or restores a settings backup file that you can keep, copy, or move to another device."
        )
      )

      Button {
        pendingFocusRestoreTarget = .settingsExport
        do {
          settingsBackupDocument = try settingsController.makeSettingsBackupDocument()
          isSettingsBackupExporterPresented = true
        } catch {
          pendingFocusRestoreTarget = nil
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
      .accessibilityFocused($focusedSettingsControl, equals: .settingsExport)

      Button {
        pendingFocusRestoreTarget = .settingsImport
        isSettingsBackupImporterPresented = true
      } label: {
        Text(L10n.text("settings.backup.import", fallback: "Import settings backup"))
      }
      .accessibilityFocused($focusedSettingsControl, equals: .settingsImport)

      Text(
        L10n.text(
          "settings.backup.file_hint",
          fallback: "Choose where to save a backup file, or restore settings from an existing backup file."
        )
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
    } header: {
      AppSectionHeader(title: L10n.text("settings.backup_restore.file.title", fallback: "Backup file"))
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
          selectedID: settingsController.state.tuningGestureDirection.rawValue,
          selectionAnnouncement: selectionAnnouncement(
            title: L10n.text("settings.tuning.direction")
          )
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
          selectedID: tuneStepSelectionID,
          selectionAnnouncement: selectionAnnouncement(
            title: L10n.text("settings.tuning.global_step")
          )
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
          selectedID: settingsController.state.frequencyEntryCommitMode.rawValue,
          selectionAnnouncement: selectionAnnouncement(
            title: L10n.text(
              "settings.tuning.typed_frequency",
              fallback: "Typed frequency"
            )
          )
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

  @ViewBuilder
  private var accessibilitySections: some View {
    Section {
      settingsSectionDescription(
        L10n.text(
          "settings.accessibility.spoken_feedback.description",
          fallback: "Choose how Listen SDR should react to Magic Tap, list selections, and RDS updates when a screen reader is active."
        )
      )

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
          selectedID: settingsController.state.magicTapAction.rawValue,
          selectionAnnouncement: selectionAnnouncement(
            title: L10n.text("settings.accessibility.magic_tap")
          )
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

      NavigationLink {
        SelectionListView(
          title: L10n.text("settings.accessibility.voiceover_rds_mode"),
          options: VoiceOverRDSAnnouncementMode.allCases.map { mode in
            SelectionListOption(id: mode.rawValue, title: mode.localizedTitle, detail: nil)
          },
          selectedID: settingsController.state.voiceOverRDSAnnouncementMode.rawValue,
          selectionAnnouncement: selectionAnnouncement(
            title: L10n.text("settings.accessibility.voiceover_rds_mode")
          )
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

      NavigationLink {
        SelectionListView(
          title: L10n.text("settings.accessibility.selection_announcements"),
          options: ScreenReaderSelectionAnnouncementMode.allCases.map { mode in
            SelectionListOption(id: mode.rawValue, title: mode.localizedTitle, detail: nil)
          },
          selectedID: settingsController.state.accessibilitySelectionAnnouncementMode.rawValue,
          selectionAnnouncement: selectionAnnouncement(
            title: L10n.text("settings.accessibility.selection_announcements")
          )
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
    } header: {
      AppSectionHeader(
        title: L10n.text(
          "settings.accessibility.spoken_feedback.section",
          fallback: "Spoken feedback"
        )
      )
    }
    .appSectionStyle()

    Section {
      settingsSectionDescription(
        L10n.text(
          "settings.accessibility.feedback_sounds.description",
          fallback: "Turn on the sound cues you want. The preview uses the current feedback sound volume."
        )
      )

      Toggle(
        L10n.text("settings.accessibility.interaction_sounds"),
        isOn: Binding(
          get: { settingsController.state.accessibilityInteractionSoundsEnabled },
          set: { settingsController.setAccessibilityInteractionSoundsEnabled($0) }
        )
      )

      Toggle(
        L10n.text("settings.accessibility.connection_sounds"),
        isOn: Binding(
          get: { settingsController.state.accessibilityConnectionSoundsEnabled },
          set: { settingsController.setAccessibilityConnectionSoundsEnabled($0) }
        )
      )

      Toggle(
        L10n.text("settings.accessibility.recording_sounds"),
        isOn: Binding(
          get: { settingsController.state.accessibilityRecordingSoundsEnabled },
          set: { settingsController.setAccessibilityRecordingSoundsEnabled($0) }
        )
      )

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

      Toggle(
        L10n.text("settings.accessibility.interaction_sounds.mute_while_recording"),
        isOn: Binding(
          get: { settingsController.state.accessibilityInteractionSoundsMutedDuringRecording },
          set: { settingsController.setAccessibilityInteractionSoundsMutedDuringRecording($0) }
        )
      )
      .disabled(!settingsController.state.accessibilityInteractionSoundsEnabled)
    } header: {
      AppSectionHeader(
        title: L10n.text(
          "settings.accessibility.feedback_sounds.section",
          fallback: "Feedback sounds"
        )
      )
    }
    .appSectionStyle()

    Section {
      settingsSectionDescription(
        L10n.text(
          "settings.accessibility.speech_audio.description",
          fallback: "Keep speech-focused streams closer to one listening level. FM-DX playback and recordings stay unchanged."
        )
      )

      NavigationLink {
        SelectionListView(
          title: L10n.text(
            "settings.audio.speech_loudness_leveling",
            fallback: "Speech loudness leveling"
          ),
          options: speechLoudnessSelectionOptions(),
          selectedID: settingsController.state.accessibilitySpeechLoudnessLevelingMode.rawValue,
          selectionAnnouncement: selectionAnnouncement(
            title: L10n.text(
              "settings.audio.speech_loudness_leveling",
              fallback: "Speech loudness leveling"
            )
          )
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
    } header: {
      AppSectionHeader(
        title: L10n.text(
          "settings.accessibility.speech_audio.section",
          fallback: "Speech audio"
        )
      )
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
          selectedID: settingsController.state.radiosSearchFiltersVisibility.rawValue,
          selectionAnnouncement: selectionAnnouncement(
            title: L10n.text("settings.radios.search_filters")
          )
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

      Toggle(
        L10n.text("settings.radios.keep_station_presets_expanded"),
        isOn: Binding(
          get: { settingsController.state.keepStationPresetsExpanded },
          set: { settingsController.setKeepStationPresetsExpanded($0) }
        )
      )
      .accessibilityHint(L10n.text("settings.radios.keep_station_presets_expanded.hint"))
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
          selectedID: settingsController.state.channelScannerInterferenceFilterProfile.rawValue,
          selectionAnnouncement: selectionAnnouncement(
            title: L10n.text("settings.scanner.interference_profile")
          )
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
          selectedID: settingsController.state.fmdxBandScanStartBehavior.rawValue,
          selectionAnnouncement: selectionAnnouncement(
            title: L10n.text("settings.scanner.fmdx_start_behavior")
          )
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
          selectedID: settingsController.state.fmdxBandScanHitBehavior.rawValue,
          selectionAnnouncement: selectionAnnouncement(
            title: L10n.text("settings.scanner.fmdx_hit_behavior")
          )
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

  @ViewBuilder
  private var audioSections: some View {
    Section {
      settingsSectionDescription(
        L10n.text(
          "settings.audio.playback.description",
          fallback: "Control playback behavior that applies before FM-DX tuning and recording settings."
        )
      )

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
          selectedID: settingsController.state.audioSuggestionScope.rawValue,
          selectionAnnouncement: selectionAnnouncement(
            title: L10n.text("settings.audio.suggestion_scope")
          )
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

      SettingsLiveAudioInsightSection()
    } header: {
      AppSectionHeader(
        title: L10n.text(
          "settings.audio.playback.section",
          fallback: "Playback"
        )
      )
    }
    .appSectionStyle()

    Section {
      settingsSectionDescription(
        L10n.text(
          "settings.audio.fmdx.description",
          fallback: "Choose a ready FM-DX audio profile or fine-tune the stream buffers manually."
        )
      )

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
          selectedID: settingsController.state.currentFMDXAudioPreset.rawValue,
          selectionAnnouncement: selectionAnnouncement(
            title: L10n.text("settings.audio.preset")
          )
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
      AppSectionHeader(
        title: L10n.text(
          "settings.audio.fmdx.section",
          fallback: "FM-DX audio"
        )
      )
    }
    .appSectionStyle()

    Section {
      settingsSectionDescription(
        L10n.text(
          "settings.audio.recording.description",
          fallback: "Choose where new recordings should be saved. The default location stays inside the app."
        )
      )

      LabeledContent(
        L10n.text(
          "settings.audio.recording_folder",
          fallback: "Recording folder"
        ),
        value: recordingStore.recordingDestinationSummary
      )

      Button {
        pendingFocusRestoreTarget = .recordingFolder
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
      .accessibilityFocused($focusedSettingsControl, equals: .recordingFolder)

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
    } header: {
      AppSectionHeader(
        title: L10n.text(
          "settings.audio.recording.section",
          fallback: "Recording"
        )
      )
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
        Text(
          L10n.text(
            "settings.diagnostics.reconnect",
            fallback: "Reconnect"
          )
        )
      }
      .disabled(!settingsController.state.canReconnectSelectedProfile)

      FocusRetainingButton {
        settingsController.resetDSPSettings()
      } label: {
        Text(
          L10n.text(
            "settings.diagnostics.reset_signal",
            fallback: "Reset signal settings"
          )
        )
      }

      settingsInfoBlock(
        title: L10n.text(
          "settings.diagnostics.reset_signal",
          fallback: "Reset signal settings"
        ),
        description: L10n.text(
          "settings.diagnostics.reset_signal.description",
          fallback: "Restores demodulation mode and signal processing controls to their defaults. The exact range depends on the receiver type."
        )
      )
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

  private var supportSection: some View {
    Section {
      SupportDevelopmentCard(
        descriptionText: L10n.text(
          "settings.support.body",
          fallback: "If you enjoy Listen SDR and want to support its development, you can contribute through PayPal. Every contribution helps fund accessibility work, fixes, and new features."
        ),
        showsCopyLinkButton: true
      )
    } header: {
      AppSectionHeader(
        title: L10n.text(
          "settings.support.section",
          fallback: "Support development"
        )
      )
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
        .foregroundStyle(AppTheme.secondaryText)
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

  private var startupConnectionSummary: String {
    L10n.text(
      "settings.summary.startup_connection.overview",
      fallback: "Startup, network and receiver connection"
    )
  }

  private var tuningScanningSummary: String {
    L10n.text(
      "settings.summary.tuning_scanning.overview",
      fallback: "Tuning, scanner and FM-DX settings"
    )
  }

  private var historyRadiosSummary: String {
    L10n.text(
      "settings.summary.history_radios.overview",
      fallback: "Listening history and receiver profiles"
    )
  }

  private var audioSettingsSummary: String {
    L10n.text(
      "settings.summary.audio.overview",
      fallback: "Playback, speech and recording"
    )
  }

  private var appearanceSettingsSummary: String {
    L10n.text(
      "settings.summary.appearance.overview",
      fallback: "Skins, colors and interface appearance"
    )
  }

  private var accessibilitySettingsSummary: String {
    L10n.text(
      "settings.summary.accessibility.overview",
      fallback: "VoiceOver, sounds and announcements"
    )
  }

  private var backupRestoreSummary: String {
    L10n.text(
      "settings.summary.backup_restore.overview",
      fallback: "Settings backup, import and restore"
    )
  }

  private var diagnosticsFeedbackSummary: String {
    L10n.text(
      "settings.summary.diagnostics_feedback.overview",
      fallback: "Logs, diagnostics and feedback"
    )
  }

  private var helpPrivacySummary: String {
    L10n.text(
      "settings.summary.help_privacy.overview",
      fallback: "Tutorial, support and privacy"
    )
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

  private func appearanceThemeOptions() -> [SelectionListOption] {
    AppThemeOption.allCases.map { theme in
      SelectionListOption(
        id: theme.rawValue,
        title: theme.localizedTitle,
        detail: theme.localizedDetail
      )
    }
  }

  private var selectedThemeOption: AppThemeOption {
    AppThemeOption(rawValue: selectedThemeID) ?? .classic
  }

  private var selectedThemeTitle: String {
    selectedThemeOption.localizedTitle
  }

  private var selectedThemeDetail: String {
    selectedThemeOption.localizedDetail
  }

  @ViewBuilder
  private var settingsStatusSection: some View {
    if let inlineStatus {
      Section {
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: inlineStatus.symbolName)
            .font(.title3)
            .foregroundStyle(inlineStatus.tintColor)

          VStack(alignment: .leading, spacing: 4) {
            Text(inlineStatus.title)
              .font(.headline)

            if let message = inlineStatus.message, !message.isEmpty {
              Text(message)
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
            }
          }

          Spacer(minLength: 8)

          Button {
            self.inlineStatus = nil
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(AppTheme.secondaryText)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(
            L10n.text(
              "settings.status.dismiss",
              fallback: "Dismiss status"
            )
          )
        }
        .padding(.vertical, 4)
      }
      .appSectionStyle()
    }
  }

  @ViewBuilder
  private func settingsRowLabel(title: String, summary: String?) -> some View {
    if let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      LabeledContent(title, value: summary)
    } else {
      Text(title)
    }
  }

  private func settingsSectionDescription(_ text: String) -> some View {
    Text(text)
      .font(.footnote)
      .foregroundStyle(AppTheme.secondaryText)
  }

  private func presentInlineStatus(
    title: String,
    message: String? = nil,
    kind: SettingsInlineStatus.Kind = .success
  ) {
    inlineStatus = SettingsInlineStatus(kind: kind, title: title, message: message)
    let announcement = [title, message]
      .compactMap { value in
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
      }
      .joined(separator: ". ")
    AppAccessibilityAnnouncementCenter.post(announcement)
  }

  private func restoreFocusIfNeeded(for target: SettingsFocusTarget) {
    guard pendingFocusRestoreTarget == target else { return }
    pendingFocusRestoreTarget = nil

    guard UIAccessibility.isVoiceOverRunning else { return }

    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 180_000_000)
      focusedSettingsControl = target
    }
  }

  private func copyCustomThemeToClipboard() {
    do {
      UIPasteboard.general.string = try AppTheme.exportCustomThemeJSONString()
      presentInlineStatus(
        title: L10n.text(
          "settings.appearance.custom.export.success.title",
          fallback: "Custom skin copied"
        ),
        message: L10n.text(
          "settings.appearance.custom.export.success.body",
          fallback: "The custom skin JSON was copied to the clipboard."
        )
      )
    } catch {
      activeAlert = FeedbackServerAlert(
        title: L10n.text(
          "settings.appearance.custom.export.failure.title",
          fallback: "Unable to export custom skin"
        ),
        message: error.localizedDescription
      )
    }
  }

  private func importCustomThemeFromClipboard() {
    applyImportedCustomTheme(UIPasteboard.general.string ?? "")
  }

  private func applyImportedCustomTheme(_ rawValue: String) {
    do {
      try AppTheme.importCustomTheme(from: rawValue)
      selectedThemeID = AppThemeOption.custom.rawValue
      customThemeImportPayload = try AppTheme.exportCustomThemeJSONString()
      isCustomThemeImportSheetPresented = false
      presentInlineStatus(
        title: L10n.text(
          "settings.appearance.custom.import.success.title",
          fallback: "Custom skin imported"
        ),
        message: L10n.text(
          "settings.appearance.custom.import.success.body",
          fallback: "The imported custom skin is now active."
        )
      )
    } catch {
      activeAlert = FeedbackServerAlert(
        title: L10n.text(
          "settings.appearance.custom.import.failure.title",
          fallback: "Unable to import custom skin"
        ),
        message: error.localizedDescription
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
            presentInlineStatus(
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

private enum SettingsFocusTarget: Hashable {
  case recordingFolder
  case settingsExport
  case settingsImport
  case customThemeImport
}

private struct SettingsInlineStatus: Identifiable, Equatable {
  enum Kind: Equatable {
    case success
    case info
  }

  let id = UUID()
  let kind: Kind
  let title: String
  let message: String?

  var symbolName: String {
    switch kind {
    case .success:
      return "checkmark.circle.fill"
    case .info:
      return "info.circle.fill"
    }
  }

  var tintColor: Color {
    switch kind {
    case .success:
      return AppTheme.tint
    case .info:
      return AppTheme.accent
    }
  }
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
