import SwiftUI
import UIKit

private enum ScanSource: String, CaseIterable, Identifiable {
  case favorites
  case serverBookmarks
  case quickList

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .favorites:
      return L10n.text("scan_source.favorites")
    case .serverBookmarks:
      return L10n.text("scan_source.server_list")
    case .quickList:
      return L10n.text("scan_source.quick_list")
    }
  }
}

struct ReceiverView: View {
  @EnvironmentObject private var profileStore: ProfileStore
  @EnvironmentObject private var radioSession: RadioSessionViewModel
  @EnvironmentObject private var presetStore: FrequencyPresetStore
  @State private var isSavePresetSheetPresented = false
  @State private var isManualPresetSheetPresented = false
  @State private var isFrequencyEntrySheetPresented = false
  @State private var presetNameDraft = ""
  @State private var manualPresetNameDraft = ""
  @State private var manualPresetFrequencyDraft = ""
  @State private var manualPresetModeDraft: DemodulationMode = .fm
  @State private var manualPresetError: String?
  @State private var frequencyInputDraft = ""
  @State private var frequencyInputError: String?
  @State private var frequencyInputHintText = ""
  @State private var frequencyInputPlaceholderText = ""
  @State private var isImportingFMDXPresets = false
  @State private var fmdxPresetImportStatusText: String?
  @State private var autoImportedFMDXProfileIDs: Set<UUID> = []
  @State private var scanSource: ScanSource = .favorites
  @State private var quickScanChannels: [ScanChannel] = []
  @State private var scannerDwellSeconds: Double = 1.5
  @State private var scannerHoldSeconds: Double = 4.0
  @State private var isFMDXDetailsExpanded = false
  @State private var isFMDXStationListExpanded = true
  @State private var isFMDXServerSlotsExpanded = false
  @FocusState private var isFrequencyInputFocused: Bool

  private let defaultFrequencyRangeHz: ClosedRange<Int> = 100_000...3_000_000_000
  private let kiwiFrequencyRangeHz: ClosedRange<Int> = 10_000...32_000_000
  private let fmDxFrequencyRangeHz: ClosedRange<Int> = 64_000_000...110_000_000
  private let fmDxFMTuneStepOptionsHz: [Int] = [25_000, 50_000, 100_000, 200_000]
  private let fmDxAMTuneStepOptionsHz: [Int] = [9_000, 10_000, 25_000, 50_000]
  private let fmDxScannerAutoStepHz = 100_000

  var body: some View {
    NavigationStack {
      Group {
        if let selectedProfile = profileStore.selectedProfile {
          receiverForm(for: selectedProfile)
        } else {
          UnavailableContentView(
            title: L10n.text("No Selected Radio"),
            systemImage: "antenna.radiowaves.left.and.right",
            description: L10n.text("Add and select a receiver profile in the Radios tab.")
          )
        }
      }
      .navigationTitle("Receiver")
      .sheet(isPresented: $isSavePresetSheetPresented) {
        savePresetSheet
      }
      .sheet(isPresented: $isManualPresetSheetPresented) {
        manualPresetSheet
      }
      .sheet(isPresented: $isFrequencyEntrySheetPresented) {
        frequencyEntrySheet
      }
      .appScreenBackground()
    }
  }

  private func receiverForm(for profile: SDRConnectionProfile) -> some View {
    let presets = visiblePresets(for: profile)
    let scannerChannels = scanChannels(for: profile, presets: presets)
    let tuningRange = frequencyRange(for: profile.backend)

    return Form {
      connectionSection(for: profile)
      tuningSection(for: profile, tuningRange: tuningRange)
      openWebRXControlsSection(for: profile)
      openWebRXServerBookmarksSection(for: profile)
      openWebRXBandPlanSection(for: profile)
      kiwiControlsSection(for: profile)
      fmDxControlsSection(for: profile)
      fmDxServerPresetsSection(for: profile)
      fmDxUserPresetsSection(for: profile, presets: presets)
      if profile.backend != .fmDxWebserver {
        scannerSection(for: profile, scannerChannels: scannerChannels)
      }
      fmDxLiveSection(for: profile)
      kiwiLiveSection(for: profile)
      audioSection()
    }
    .scrollContentBackground(.hidden)
  }

  private func connectionSection(for profile: SDRConnectionProfile) -> some View {
    Section("Connection") {
      LabeledContent("Profile", value: profile.name)
        .accessibilityLabel(L10n.text("Selected profile"))
        .accessibilityValue(profile.name)

      LabeledContent("Backend", value: profile.backend.displayName)
      LabeledContent("Endpoint", value: profile.endpointDescription)

      LabeledContent("Status", value: radioSession.statusText)
        .accessibilityLabel(L10n.text("Connection status"))
        .accessibilityValue(radioSession.statusText)

      if let backendStatus = radioSession.backendStatusText, !backendStatus.isEmpty {
        LabeledContent("Receiver data", value: backendStatus)
          .accessibilityLabel(L10n.text("Receiver live data"))
          .accessibilityValue(backendStatus)
      }

      if let error = radioSession.lastError {
        Text(error)
          .foregroundStyle(.red)
          .font(.footnote)
          .accessibilityLabel(L10n.text("Last error"))
          .accessibilityValue(error)
      }

      Button(action: {
        if radioSession.state == .connected &&
          radioSession.connectedProfileID == profile.id {
          radioSession.disconnect()
        } else {
          radioSession.connect(to: profile)
        }
      }) {
        Text(connectionButtonTitle(for: profile))
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .accessibilityHint(L10n.text("Double tap to change connection state"))

      if radioSession.state == .failed {
        Button {
          radioSession.reconnect(to: profile)
        } label: {
          Text("Reconnect")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityHint(L10n.text("Try connecting to this receiver again"))
      }
    }
    .appSectionStyle()
  }

  private func tuningSection(for profile: SDRConnectionProfile, tuningRange: ClosedRange<Int>) -> some View {
    Section("Tuning") {
      LabeledContent(
        "Frequency",
        value: frequencyText(
          fromHz: radioSession.settings.frequencyHz,
          backend: profile.backend
        )
      )

      frequencySlider(for: profile.backend, tuningRange: tuningRange)

      Button {
        beginFrequencyEntry()
      } label: {
        Label("Set exact frequency", systemImage: "number")
      }
      .accessibilityHint(L10n.text("Enter frequency in hertz, kilohertz or megahertz"))

      tuneStepControl(for: profile.backend)

      Picker(
        "Mode",
        selection: Binding(
          get: {
            let allowed = availableModes(for: profile.backend)
            return allowed.contains(radioSession.settings.mode) ? radioSession.settings.mode : allowed.first ?? .fm
          },
          set: { radioSession.setMode($0) }
        )
      ) {
        ForEach(availableModes(for: profile.backend)) { mode in
          Text(mode.displayName).tag(mode)
        }
      }
      .accessibilityLabel("Demodulation mode")

      if let tuneWarning = radioSession.fmdxTuneWarningText,
        profile.backend == .fmDxWebserver {
        Text(tuneWarning)
          .font(.footnote)
          .foregroundStyle(.orange)
      }
    }
    .appSectionStyle()
  }

  @ViewBuilder
  private func openWebRXControlsSection(for profile: SDRConnectionProfile) -> some View {
    if profile.backend == .openWebRX {
      Section(L10n.text("openwebrx.controls")) {
        if radioSession.state == .connected &&
          radioSession.connectedProfileID == profile.id {
          if radioSession.openWebRXProfiles.isEmpty {
            Text(L10n.text("openwebrx.controls.waiting_profiles"))
              .foregroundStyle(.secondary)
          } else {
            Picker(
              L10n.text("openwebrx.server_profile"),
              selection: Binding(
                get: {
                  radioSession.selectedOpenWebRXProfileID ?? radioSession.openWebRXProfiles.first?.id ?? ""
                },
                set: { value in
                  if !value.isEmpty {
                    radioSession.selectOpenWebRXProfile(value)
                  }
                }
              )
            ) {
              ForEach(radioSession.openWebRXProfiles) { profileOption in
                Text(profileOption.name).tag(profileOption.id)
              }
            }
            .pickerStyle(.menu)
            .accessibilityHint(L10n.text("Select SDR profile from OpenWebRX server"))
          }
        } else {
          Text(L10n.text("openwebrx.controls.connect_to_load"))
            .foregroundStyle(.secondary)
            .font(.footnote)
        }

        Toggle(
          L10n.text("openwebrx.squelch"),
          isOn: Binding(
            get: { radioSession.settings.squelchEnabled },
            set: { radioSession.setSquelchEnabled($0) }
          )
        )
        .disabled(radioSession.state != .connected)
        .accessibilityHint(L10n.text("openwebrx.squelch_hint"))

        if radioSession.settings.squelchEnabled {
          VStack(alignment: .leading, spacing: 6) {
            LabeledContent(
              L10n.text("openwebrx.squelch_level"),
              value: "\(radioSession.settings.openWebRXSquelchLevel) dB"
            )
            Slider(
              value: Binding(
                get: { Double(radioSession.settings.openWebRXSquelchLevel) },
                set: { radioSession.setOpenWebRXSquelchLevel(Int($0.rounded())) }
              ),
              in: -150 ... -20,
              step: 1
            )
          }
          .disabled(radioSession.state != .connected)
          .accessibilityElement(children: .combine)
          .accessibilityLabel(L10n.text("openwebrx.squelch_level"))
          .accessibilityValue("\(radioSession.settings.openWebRXSquelchLevel) dB")
        }

        if let activeBand = activeOpenWebRXBandName() {
          LabeledContent(L10n.text("openwebrx.current_band"), value: activeBand)
        }
      }
      .appSectionStyle()
    }
  }

  @ViewBuilder
  private func openWebRXServerBookmarksSection(for profile: SDRConnectionProfile) -> some View {
    if profile.backend == .openWebRX {
      Section("Server Bookmarks") {
        if radioSession.serverBookmarks.isEmpty {
          Text("No OpenWebRX bookmarks yet.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(radioSession.serverBookmarks) { bookmark in
            Button {
              radioSession.applyServerBookmark(bookmark)
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(bookmark.name)
                Text(FrequencyFormatter.mhzText(fromHz: bookmark.frequencyHz))
                  .font(.footnote)
                  .foregroundStyle(.secondary)
              }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
              Button("Save") {
                saveBookmarkAsPreset(bookmark, profile: profile)
              }
            }
          }
        }
      }
      .appSectionStyle()
    }
  }

  @ViewBuilder
  private func openWebRXBandPlanSection(for profile: SDRConnectionProfile) -> some View {
    if profile.backend == .openWebRX {
      Section("Band Plan") {
        if radioSession.openWebRXBandPlan.isEmpty {
          Text("Band plan is loading...")
            .foregroundStyle(.secondary)
        } else {
          ForEach(radioSession.openWebRXBandPlan) { band in
            DisclosureGroup {
              Button {
                radioSession.tuneToBand(band)
              } label: {
                Label("Tune band center", systemImage: "scope")
              }

              ForEach(Array(band.frequencies.prefix(8))) { item in
                Button {
                  radioSession.tuneToBand(band, using: item)
                } label: {
                  HStack {
                    Text(item.name)
                    Spacer()
                    Text(FrequencyFormatter.mhzText(fromHz: item.frequencyHz))
                      .foregroundStyle(.secondary)
                  }
                }
              }
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(band.name)
                Text(band.rangeText)
                  .font(.footnote)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
      }
      .appSectionStyle()
    }
  }

  @ViewBuilder
  private func fmDxControlsSection(for profile: SDRConnectionProfile) -> some View {
    if profile.backend == .fmDxWebserver {
      Section(L10n.text("fmdx.controls")) {
        fmDxAudioModePicker()

        Toggle(
          "AGC",
          isOn: Binding(
            get: { radioSession.settings.agcEnabled },
            set: { radioSession.setAGCEnabled($0) }
          )
        )
        .disabled(radioSession.state != .connected)

        Toggle(
          "cEQ Filter",
          isOn: Binding(
            get: { radioSession.settings.noiseReductionEnabled },
            set: { radioSession.setNoiseReductionEnabled($0) }
          )
        )
        .disabled(radioSession.state != .connected)

        Toggle(
          "iMS+ Filter",
          isOn: Binding(
            get: { radioSession.settings.imsEnabled },
            set: { radioSession.setIMSEnabled($0) }
          )
        )
        .disabled(radioSession.state != .connected)

        fmDxAntennaPicker()
        fmDxBandwidthPicker()
      }
      .appSectionStyle()
    }
  }

  @ViewBuilder
  private func fmDxServerPresetsSection(for profile: SDRConnectionProfile) -> some View {
    if profile.backend == .fmDxWebserver {
      let stationList = radioSession.fmdxServerPresets.filter { $0.source != "fmdx-static" }
      let serverSlots = radioSession.fmdxServerPresets.filter { $0.source == "fmdx-static" }

      Section {
        Button {
          withAnimation(.easeInOut(duration: 0.2)) {
            isFMDXStationListExpanded.toggle()
          }
        } label: {
          Label(
            L10n.text(
              isFMDXStationListExpanded
                ? "fmdx.station_list.collapse"
                : "fmdx.station_list.expand"
            ),
            systemImage: isFMDXStationListExpanded ? "chevron.up" : "chevron.down"
          )
        }

        if !serverSlots.isEmpty {
          Button {
            withAnimation(.easeInOut(duration: 0.2)) {
              isFMDXServerSlotsExpanded.toggle()
            }
          } label: {
            Label(
              L10n.text(
                isFMDXServerSlotsExpanded
                  ? "fmdx.server_slots.collapse"
                  : "fmdx.server_slots.expand"
              ),
              systemImage: isFMDXServerSlotsExpanded ? "chevron.up" : "chevron.down"
            )
          }
        }
      }
      .appSectionStyle()

      if isFMDXStationListExpanded {
        Section(L10n.text("fmdx.server_presets.section")) {
          if stationList.isEmpty {
            Text(L10n.text("fmdx.server_presets.empty"))
              .foregroundStyle(.secondary)
              .font(.footnote)
          } else {
            ForEach(stationList) { preset in
              fmdxServerBookmarkRow(preset: preset, profile: profile)
            }
          }
        }
        .appSectionStyle()
      }

      if !serverSlots.isEmpty && isFMDXServerSlotsExpanded {
        Section(L10n.text("fmdx.server_slots.section")) {
          ForEach(serverSlots) { preset in
            fmdxServerBookmarkRow(preset: preset, profile: profile)
          }
        }
        .appSectionStyle()
      }
    }
  }

  private func fmdxServerBookmarkRow(
    preset: SDRServerBookmark,
    profile: SDRConnectionProfile
  ) -> some View {
    Button {
      radioSession.setFrequencyHz(preset.frequencyHz)
    } label: {
      HStack {
        Text(preset.name)
        Spacer()
        Text(FrequencyFormatter.fmDxMHzText(fromHz: preset.frequencyHz))
          .foregroundStyle(.secondary)
      }
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      Button(L10n.text("fmdx.af.favorite")) {
        saveAFAsPreset(preset.frequencyHz, profile: profile)
      }
    }
  }

  @ViewBuilder
  private func fmDxUserPresetsSection(for profile: SDRConnectionProfile, presets: [FrequencyPreset]) -> some View {
    if profile.backend == .fmDxWebserver {
      Section(L10n.text("fmdx.user_presets.section")) {
        Button {
          beginSavingCurrentFrequency()
        } label: {
          Label(L10n.text("fmdx.user_presets.add_current"), systemImage: "plus.circle")
        }

        Button {
          beginManualPresetEntry(for: profile)
        } label: {
          Label(L10n.text("fmdx.user_presets.add_manual"), systemImage: "square.and.pencil")
        }

        Button {
          importFMDXPluginPresets(from: profile)
        } label: {
          if isImportingFMDXPresets {
            HStack(spacing: 8) {
              ProgressView()
              Text(L10n.text("fmdx.user_presets.importing"))
            }
          } else {
            Label(L10n.text("fmdx.user_presets.import_server"), systemImage: "arrow.down.circle")
          }
        }
        .disabled(isImportingFMDXPresets)

        if let statusText = fmdxPresetImportStatusText, !statusText.isEmpty {
          Text(statusText)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

        if presets.isEmpty {
          Text(L10n.text("fmdx.user_presets.empty"))
            .foregroundStyle(.secondary)
            .font(.footnote)
        } else {
          ForEach(presets) { preset in
            Button {
              apply(preset: preset)
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(preset.name)
                Text("\(frequencyText(fromHz: preset.frequencyHz, backend: profile.backend)) - \(preset.mode.displayName)")
                  .font(.footnote)
                  .foregroundStyle(.secondary)
              }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
              Button("Delete", role: .destructive) {
                presetStore.removePreset(preset)
              }
            }
          }
        }
      }
      .appSectionStyle()
      .onAppear {
        autoImportFMDXPluginPresetsIfNeeded(for: profile)
      }
    }
  }

  @ViewBuilder
  private func kiwiControlsSection(for profile: SDRConnectionProfile) -> some View {
    if profile.backend == .kiwiSDR {
      Section(L10n.text("kiwi.controls")) {
        Toggle(
          L10n.text("kiwi.agc"),
          isOn: Binding(
            get: { radioSession.settings.agcEnabled },
            set: { radioSession.setAGCEnabled($0) }
          )
        )
        .disabled(radioSession.state != .connected)
        .accessibilityHint(L10n.text("kiwi.agc_hint"))

        if !radioSession.settings.agcEnabled {
          VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("receiver.rf_gain_value", Int(radioSession.settings.rfGain)))
            Slider(
              value: Binding(
                get: { radioSession.settings.rfGain },
                set: { radioSession.setRFGain($0) }
              ),
              in: 0...100,
              step: 1
            )
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel(L10n.text("RF gain"))
          .accessibilityValue("\(Int(radioSession.settings.rfGain))")
          .disabled(radioSession.state != .connected)
        }

        Toggle(
          L10n.text("kiwi.squelch"),
          isOn: Binding(
            get: { radioSession.settings.squelchEnabled },
            set: { radioSession.setSquelchEnabled($0) }
          )
        )
        .disabled(radioSession.state != .connected)
        .accessibilityHint(L10n.text("kiwi.squelch_hint"))

        if radioSession.settings.squelchEnabled {
          VStack(alignment: .leading, spacing: 6) {
            LabeledContent(
              L10n.text("kiwi.squelch_level"),
              value: "\(radioSession.settings.kiwiSquelchThreshold)"
            )
            Slider(
              value: Binding(
                get: { Double(radioSession.settings.kiwiSquelchThreshold) },
                set: { radioSession.setKiwiSquelchThreshold(Int($0.rounded())) }
              ),
              in: 0 ... 30,
              step: 1
            )
          }
          .disabled(radioSession.state != .connected)
          .accessibilityElement(children: .combine)
          .accessibilityLabel(L10n.text("kiwi.squelch_level"))
          .accessibilityValue("\(radioSession.settings.kiwiSquelchThreshold)")
        }

        Picker(
          L10n.text("kiwi.waterfall.speed"),
          selection: Binding(
            get: { radioSession.settings.kiwiWaterfallSpeed },
            set: { radioSession.setKiwiWaterfallSpeed($0) }
          )
        ) {
          ForEach([1, 2, 4, 8], id: \.self) { speed in
            Text("x\(speed)").tag(speed)
          }
        }
        .disabled(radioSession.state != .connected)

        VStack(alignment: .leading, spacing: 6) {
          LabeledContent(
            L10n.text("kiwi.waterfall.zoom"),
            value: "\(radioSession.settings.kiwiWaterfallZoom)"
          )
          Slider(
            value: Binding(
              get: { Double(radioSession.settings.kiwiWaterfallZoom) },
              set: { radioSession.setKiwiWaterfallZoom(Int($0.rounded())) }
            ),
            in: 0 ... 14,
            step: 1
          )
        }
        .disabled(radioSession.state != .connected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.text("kiwi.waterfall.zoom"))
        .accessibilityValue("\(radioSession.settings.kiwiWaterfallZoom)")

        VStack(alignment: .leading, spacing: 6) {
          LabeledContent(
            L10n.text("kiwi.waterfall.min_db"),
            value: "\(radioSession.settings.kiwiWaterfallMinDB) dB"
          )
          Slider(
            value: Binding(
              get: { Double(radioSession.settings.kiwiWaterfallMinDB) },
              set: { radioSession.setKiwiWaterfallMinDB(Int($0.rounded())) }
            ),
            in: -190 ... -10,
            step: 1
          )
        }
        .disabled(radioSession.state != .connected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.text("kiwi.waterfall.min_db"))
        .accessibilityValue("\(radioSession.settings.kiwiWaterfallMinDB) dB")

        VStack(alignment: .leading, spacing: 6) {
          LabeledContent(
            L10n.text("kiwi.waterfall.max_db"),
            value: "\(radioSession.settings.kiwiWaterfallMaxDB) dB"
          )
          Slider(
            value: Binding(
              get: { Double(radioSession.settings.kiwiWaterfallMaxDB) },
              set: { radioSession.setKiwiWaterfallMaxDB(Int($0.rounded())) }
            ),
            in: -120 ... 30,
            step: 1
          )
        }
        .disabled(radioSession.state != .connected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.text("kiwi.waterfall.max_db"))
        .accessibilityValue("\(radioSession.settings.kiwiWaterfallMaxDB) dB")
      }
      .appSectionStyle()
    }
  }

  private func fmDxAudioModePicker() -> some View {
    let isForcedStereo = radioSession.fmdxTelemetry?.isForcedStereo ?? false
    let modeText = isForcedStereo
      ? L10n.text("fmdx.stereo_state.stereo")
      : L10n.text("fmdx.stereo_state.mono")

    return Button {
      radioSession.setFMDXForcedStereoEnabled(!isForcedStereo)
    } label: {
      HStack {
        Text(L10n.text("fmdx.audio_mode"))
        Spacer()
        Text(modeText)
          .fontWeight(.semibold)
      }
    }
    .disabled(radioSession.state != .connected)
    .accessibilityLabel(L10n.text("fmdx.audio_mode"))
    .accessibilityValue(modeText)
  }

  @ViewBuilder
  private func fmDxAntennaPicker() -> some View {
    if !radioSession.fmdxCapabilities.antennas.isEmpty {
      let selection = Binding<String>(
        get: {
          radioSession.selectedFMDXAntennaID
            ?? radioSession.fmdxCapabilities.antennas.first?.id
            ?? ""
        },
        set: { value in
          if !value.isEmpty {
            radioSession.setFMDXAntenna(value)
          }
        }
      )

      Picker(L10n.text("fmdx.antenna"), selection: selection) {
        ForEach(radioSession.fmdxCapabilities.antennas) { option in
          Text(option.label).tag(option.id)
        }
      }
      .disabled(radioSession.state != .connected)
    }
  }

  @ViewBuilder
  private func fmDxBandwidthPicker() -> some View {
    if !radioSession.fmdxCapabilities.bandwidths.isEmpty {
      let selection = Binding<String>(
        get: {
          radioSession.selectedFMDXBandwidthID
            ?? radioSession.fmdxCapabilities.bandwidths.first?.id
            ?? ""
        },
        set: { value in
          guard let option = radioSession.fmdxCapabilities.bandwidths.first(where: { $0.id == value }) else { return }
          radioSession.setFMDXBandwidth(option)
        }
      )

      Picker(L10n.text("fmdx.bandwidth"), selection: selection) {
        ForEach(radioSession.fmdxCapabilities.bandwidths) { option in
          Text(option.label).tag(option.id)
        }
      }
      .disabled(radioSession.state != .connected)
    }
  }

  private func scannerSection(for profile: SDRConnectionProfile, scannerChannels: [ScanChannel]) -> some View {
    Section("Scanner") {
      Picker("Channel source", selection: $scanSource) {
        ForEach(ScanSource.allCases) { source in
          Text(source.displayName).tag(source)
        }
      }

      if scanSource == .quickList {
        Button(L10n.text("scanner.quick_list.clear")) {
          quickScanChannels.removeAll()
        }
        .disabled(quickScanChannels.isEmpty)
      }

      LabeledContent("Channels", value: "\(scannerChannels.count)")

      Slider(
        value: $radioSession.scannerThreshold,
        in: thresholdRange(for: profile.backend),
        step: thresholdStep(for: profile.backend)
      )
      LabeledContent(
        "Threshold",
        value: "\(String(format: "%.1f", radioSession.scannerThreshold)) \(radioSession.scannerSignalUnit(for: profile.backend))"
      )

      VStack(alignment: .leading, spacing: 6) {
        LabeledContent("Dwell", value: "\(String(format: "%.1f", scannerDwellSeconds)) s")
        Slider(value: $scannerDwellSeconds, in: 0.5...6, step: 0.1)
      }

      VStack(alignment: .leading, spacing: 6) {
        LabeledContent("Hold on hit", value: "\(String(format: "%.1f", scannerHoldSeconds)) s")
        Slider(value: $scannerHoldSeconds, in: 0.5...12, step: 0.1)
      }

      if radioSession.isScannerRunning {
        Button("Stop scanner") {
          radioSession.stopScanner()
        }
        .buttonStyle(.borderedProminent)
      } else {
        Button("Start scanner") {
          radioSession.startScanner(
            channels: scannerChannels,
            backend: profile.backend,
            dwellSeconds: scannerDwellSeconds,
            holdSeconds: scannerHoldSeconds
          )
        }
        .buttonStyle(.borderedProminent)
        .disabled(scannerChannels.isEmpty || radioSession.state != .connected)
      }

      if let scannerStatus = radioSession.scannerStatusText {
        Text(scannerStatus)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      if profile.backend == .openWebRX {
        Text("Threshold hold works with live signal metrics (KiwiSDR and FM-DX).")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .appSectionStyle()
  }

  @ViewBuilder
  private func fmDxLiveSection(for profile: SDRConnectionProfile) -> some View {
    if profile.backend == .fmDxWebserver, let telemetry = radioSession.fmdxTelemetry {
      Section(L10n.text("fmdx.live.section")) {
        if let signal = telemetry.signal {
          LabeledContent(L10n.text("fmdx.field.signal"), value: String(format: "%.1f dBf", signal))
        }
        if let signalTop = telemetry.signalTop {
          LabeledContent(L10n.text("fmdx.field.signal_peak"), value: String(format: "%.1f dBf", signalTop))
        }
        if let users = telemetry.users {
          LabeledContent(L10n.text("fmdx.field.users"), value: "\(users)")
        }
        if let pi = telemetry.pi, !pi.isEmpty {
          LabeledContent("PI", value: pi)
        }
        if let ps = telemetry.ps, !ps.isEmpty {
          LabeledContent("PS", value: ps)
        }
        if let countryName = telemetry.countryName, !countryName.isEmpty {
          LabeledContent(L10n.text("fmdx.field.country"), value: countryName)
        }
        if let countryISO = telemetry.countryISO, !countryISO.isEmpty {
          LabeledContent("ISO", value: countryISO)
        }
        if !telemetry.afMHz.isEmpty {
          ForEach(Array(telemetry.afMHz.prefix(16)), id: \.self) { afMHz in
            let afHz = frequencyHz(fromMHz: afMHz)
            HStack {
              Button(String(format: "%.1f MHz", afMHz)) {
                radioSession.setFrequencyHz(afHz)
              }
              .buttonStyle(.borderless)

              Spacer()

              Button(L10n.text("fmdx.af.favorite")) {
                saveAFAsPreset(afHz, profile: profile)
              }
              .buttonStyle(.borderless)

              Button(L10n.text("fmdx.af.scan")) {
                addQuickScanChannel(frequencyHz: afHz)
              }
              .buttonStyle(.borderless)
            }
          }
        }
        if let rt0 = telemetry.rt0, !rt0.isEmpty {
          Text(L10n.text("fmdx.rt0", rt0))
            .font(.footnote)
        }
        if let rt1 = telemetry.rt1, !rt1.isEmpty {
          Text(L10n.text("fmdx.rt1", rt1))
            .font(.footnote)
        }

        DisclosureGroup(
          L10n.text("fmdx.live.more_details"),
          isExpanded: $isFMDXDetailsExpanded
        ) {
          if let pty = telemetry.pty {
            LabeledContent("PTY", value: ptyDisplayText(pty: pty, rbds: telemetry.rbds))
          }
          if let tp = telemetry.tp {
            LabeledContent("TP", value: tp == 1 ? L10n.text("common.yes") : L10n.text("common.no"))
          }
          if let ta = telemetry.ta {
            LabeledContent("TA", value: ta == 1 ? L10n.text("common.yes") : L10n.text("common.no"))
          }
          if let ms = telemetry.ms {
            LabeledContent("MS", value: msDisplayText(ms))
          }
          if let ecc = telemetry.ecc {
            LabeledContent("ECC", value: String(format: "0x%02X", ecc))
          }
          if let rbds = telemetry.rbds {
            LabeledContent("RBDS", value: rbds ? L10n.text("common.yes") : L10n.text("common.no"))
          }
          if let agc = telemetry.agc, !agc.isEmpty {
            LabeledContent("AGC", value: agc)
          }

          Toggle(
            L10n.text("fmdx.show_rds_errors"),
            isOn: Binding(
              get: { radioSession.settings.showRdsErrorCounters },
              set: { radioSession.setShowRdsErrorCounters($0) }
            )
          )

          if radioSession.settings.showRdsErrorCounters {
            if let errors = telemetry.psErrors, !errors.isEmpty {
              Text(L10n.text("fmdx.ps_errors", errors))
                .font(.footnote)
            }
            if let errors = telemetry.rt0Errors, !errors.isEmpty {
              Text(L10n.text("fmdx.rt0_errors", errors))
                .font(.footnote)
            }
            if let errors = telemetry.rt1Errors, !errors.isEmpty {
              Text(L10n.text("fmdx.rt1_errors", errors))
                .font(.footnote)
            }
          }

          if let tx = telemetry.txInfo {
            if let station = tx.station, !station.isEmpty {
              LabeledContent("TX", value: station)
            }
            if let city = tx.city, !city.isEmpty {
              LabeledContent("City", value: city)
            }
            if let itu = tx.itu, !itu.isEmpty {
              LabeledContent("ITU", value: itu)
            }
            if let distance = tx.distanceKm, !distance.isEmpty {
              LabeledContent(L10n.text("fmdx.field.distance"), value: "\(distance) km")
            }
            if let azimuth = tx.azimuthDeg, !azimuth.isEmpty {
              LabeledContent(L10n.text("fmdx.field.azimuth"), value: "\(azimuth) deg")
            }
            if let erp = tx.erpKW, !erp.isEmpty {
              LabeledContent("ERP", value: "\(erp) kW")
            }
            if let polarization = tx.polarization, !polarization.isEmpty {
              LabeledContent(L10n.text("fmdx.field.polarization"), value: polarization)
            }
          }
        }
      }
      .appSectionStyle()
    }
  }

  @ViewBuilder
  private func kiwiLiveSection(for profile: SDRConnectionProfile) -> some View {
    if profile.backend == .kiwiSDR, let telemetry = radioSession.kiwiTelemetry {
      Section(L10n.text("kiwi.live.section")) {
        if let rssi = telemetry.rssiDBm {
          LabeledContent(L10n.text("kiwi.live.smeter"), value: String(format: "%.1f dBm", rssi))
        } else {
          LabeledContent(L10n.text("kiwi.live.smeter"), value: L10n.text("kiwi.live.no_data"))
        }
        LabeledContent(L10n.text("kiwi.live.audio_rate"), value: "\(telemetry.sampleRateHz) Hz")

        if !telemetry.waterfallBins.isEmpty {
          WaterfallStripView(bins: telemetry.waterfallBins)
            .frame(height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
              RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            }
            .accessibilityLabel(L10n.text("kiwi.live.waterfall"))
            .accessibilityValue(L10n.text("kiwi.live.waterfall"))
        } else {
          Text(L10n.text("kiwi.live.waterfall_loading"))
            .foregroundStyle(.secondary)
        }
      }
      .appSectionStyle()
    }
  }

  private func favoritesSection(presets: [FrequencyPreset]) -> some View {
    Section("Favorites") {
      Button {
        beginSavingCurrentFrequency()
      } label: {
        Label("Save current frequency", systemImage: "star")
      }
      .accessibilityHint(L10n.text("Saves current frequency and mode as a favorite"))

      if presets.isEmpty {
        Text("No favorites yet. Save one to recall frequency and mode quickly.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(presets) { preset in
          Button {
            apply(preset: preset)
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(preset.name)
              Text("\(FrequencyFormatter.mhzText(fromHz: preset.frequencyHz)) - \(preset.mode.displayName)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
          }
          .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete", role: .destructive) {
              presetStore.removePreset(preset)
            }
          }
          .accessibilityLabel(preset.name)
          .accessibilityValue("\(FrequencyFormatter.mhzText(fromHz: preset.frequencyHz)), \(preset.mode.displayName)")
          .accessibilityHint(L10n.text("Double tap to apply this favorite"))
        }
      }
    }
    .appSectionStyle()
  }

  private func audioSection() -> some View {
    Section("Audio") {
      VStack(alignment: .leading, spacing: 6) {
        Text(L10n.text("audio.volume_percent", Int((radioSession.settings.audioVolume * 100).rounded())))
        Slider(
          value: Binding(
            get: { radioSession.settings.audioVolume },
            set: { radioSession.setAudioVolume($0) }
          ),
          in: 0...1,
          step: 0.01
        )
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(L10n.text("Audio volume"))
      .accessibilityValue("\(Int((radioSession.settings.audioVolume * 100).rounded())) percent")

      Toggle(
        "Mute audio",
        isOn: Binding(
          get: { radioSession.settings.audioMuted },
          set: { radioSession.setAudioMuted($0) }
        )
      )
    }
    .appSectionStyle()
  }

  private func connectionButtonTitle(for profile: SDRConnectionProfile) -> String {
    if radioSession.state == .connecting {
      return L10n.text("connection.connecting")
    }
    if radioSession.state == .connected &&
      radioSession.connectedProfileID == profile.id {
      return L10n.text("connection.disconnect")
    }
    return L10n.text("connection.connect")
  }

  private func thresholdRange(for backend: SDRBackend) -> ClosedRange<Double> {
    switch backend {
    case .fmDxWebserver:
      return 0...120
    case .kiwiSDR, .openWebRX:
      return -140...0
    }
  }

  private func thresholdStep(for backend: SDRBackend) -> Double {
    switch backend {
    case .fmDxWebserver:
      return 1
    case .kiwiSDR, .openWebRX:
      return 0.5
    }
  }

  private func tuneStepControl(for backend: SDRBackend) -> some View {
    let stepLabel = FrequencyFormatter.tuneStepText(fromHz: radioSession.settings.tuneStepHz)
    let options = tuneStepOptions(for: backend)

    return HStack(spacing: 12) {
      Text("Tune step")
      Spacer()

      Button {
        changeTuneStep(by: -1, backend: backend)
      } label: {
        Image(systemName: "minus.circle.fill")
          .font(.title3)
      }
      .buttonStyle(.plain)

      Menu {
        ForEach(options, id: \.self) { stepHz in
          Button(FrequencyFormatter.tuneStepText(fromHz: stepHz)) {
            setTuneStepAndAnnounce(stepHz)
          }
        }
      } label: {
        Text(stepLabel)
          .font(.body.monospacedDigit())
          .frame(minWidth: 70)
      }

      Button {
        changeTuneStep(by: 1, backend: backend)
      } label: {
        Image(systemName: "plus.circle.fill")
          .font(.title3)
      }
      .buttonStyle(.plain)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Tune step")
    .accessibilityValue(stepLabel)
    .accessibilityHint(L10n.text("receiver.frequency.swipe_and_step_hint", stepLabel))
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment:
        changeTuneStep(by: 1, backend: backend)
      case .decrement:
        changeTuneStep(by: -1, backend: backend)
      @unknown default:
        break
      }
    }
    .accessibilityScrollAction { edge in
      switch edge {
      case .leading, .top:
        changeTuneStep(by: -1, backend: backend)
      case .trailing, .bottom:
        changeTuneStep(by: 1, backend: backend)
      default:
        break
      }
    }
  }

  private func tuneStepOptions(for backend: SDRBackend) -> [Int] {
    switch backend {
    case .fmDxWebserver:
      return radioSession.settings.mode == .am ? fmDxAMTuneStepOptionsHz : fmDxFMTuneStepOptionsHz
    case .kiwiSDR, .openWebRX:
      return RadioSessionSettings.supportedTuneStepsHz
    }
  }

  private func availableModes(for backend: SDRBackend) -> [DemodulationMode] {
    switch backend {
    case .fmDxWebserver:
      return [.fm, .am]
    case .kiwiSDR, .openWebRX:
      return DemodulationMode.allCases
    }
  }

  private func changeTuneStep(by offset: Int, backend: SDRBackend) {
    let steps = tuneStepOptions(for: backend)
    guard !steps.isEmpty else { return }

    let currentStep = radioSession.settings.tuneStepHz
    let currentIndex: Int
    if let exactIndex = steps.firstIndex(of: currentStep) {
      currentIndex = exactIndex
    } else {
      currentIndex = steps.enumerated().min(by: { abs($0.element - currentStep) < abs($1.element - currentStep) })?.offset ?? 0
    }

    let nextIndex = min(max(currentIndex + offset, 0), steps.count - 1)
    guard nextIndex != currentIndex else { return }
    setTuneStepAndAnnounce(steps[nextIndex])
  }

  private func setTuneStepAndAnnounce(_ stepHz: Int) {
    guard stepHz != radioSession.settings.tuneStepHz else { return }
    radioSession.setTuneStepHz(stepHz)

    let stepText = FrequencyFormatter.tuneStepText(fromHz: radioSession.settings.tuneStepHz)
    let announcement = L10n.text("receiver.tune_step.changed", stepText)
    UIAccessibility.post(notification: .announcement, argument: announcement)
  }

  private func frequencySlider(for backend: SDRBackend, tuningRange: ClosedRange<Int>) -> some View {
    let sliderBinding = Binding<Double>(
      get: { Double(radioSession.settings.frequencyHz) },
      set: { newValue in
        let stepHz = max(1, radioSession.settings.tuneStepHz)
        let snapped = Int((newValue / Double(stepHz)).rounded()) * stepHz
        radioSession.setFrequencyHz(snapped)
      }
    )
    let frequencyValue = frequencyText(fromHz: radioSession.settings.frequencyHz, backend: backend)
    let tuneStepLabel = FrequencyFormatter.tuneStepText(fromHz: radioSession.settings.tuneStepHz)

    return Slider(
      value: sliderBinding,
      in: Double(tuningRange.lowerBound)...Double(tuningRange.upperBound),
      step: Double(radioSession.settings.tuneStepHz)
    )
    .accessibilityLabel("Frequency")
    .accessibilityValue(frequencyValue)
    .accessibilityHint(L10n.text("receiver.frequency.swipe_and_step_hint", tuneStepLabel))
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment:
        radioSession.tune(byStepCount: 1)
      case .decrement:
        radioSession.tune(byStepCount: -1)
      @unknown default:
        break
      }
    }
    .accessibilityScrollAction { edge in
      switch edge {
      case .leading, .top:
        changeTuneStep(by: -1, backend: backend)
      case .trailing, .bottom:
        changeTuneStep(by: 1, backend: backend)
      default:
        break
      }
    }
    .accessibilityAction(named: Text(L10n.text("receiver.tune_step.previous_action"))) {
      changeTuneStep(by: -1, backend: backend)
    }
    .accessibilityAction(named: Text(L10n.text("receiver.tune_step.next_action"))) {
      changeTuneStep(by: 1, backend: backend)
    }
  }

  private var savePresetSheet: some View {
    NavigationStack {
      Form {
        TextField("Preset name", text: $presetNameDraft)
          .textInputAutocapitalization(.words)
          .autocorrectionDisabled()
          .accessibilityLabel(L10n.text("Preset name"))

        LabeledContent(
          "Frequency",
          value: frequencyText(fromHz: radioSession.settings.frequencyHz, backend: profileStore.selectedProfile?.backend)
        )
        LabeledContent("Mode", value: radioSession.settings.mode.displayName)
      }
      .scrollContentBackground(.hidden)
      .navigationTitle("Save Favorite")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            isSavePresetSheetPresented = false
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            saveCurrentFrequencyAsPreset()
          }
        }
      }
      .appScreenBackground()
    }
  }

  private var manualPresetSheet: some View {
    NavigationStack {
      Form {
        TextField("Preset name", text: $manualPresetNameDraft)
          .textInputAutocapitalization(.words)
          .autocorrectionDisabled()
          .accessibilityLabel(L10n.text("Preset name"))

        TextField(L10n.text("fmdx.user_presets.manual_frequency"), text: $manualPresetFrequencyDraft)
          .keyboardType(.decimalPad)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .accessibilityLabel(L10n.text("fmdx.user_presets.manual_frequency"))

        Picker(L10n.text("fmdx.user_presets.manual_mode"), selection: $manualPresetModeDraft) {
          ForEach(availableModes(for: .fmDxWebserver)) { mode in
            Text(mode.displayName).tag(mode)
          }
        }
        .accessibilityLabel(L10n.text("fmdx.user_presets.manual_mode"))

        if let manualPresetError {
          Text(manualPresetError)
            .foregroundStyle(.red)
            .font(.footnote)
        }
      }
      .scrollContentBackground(.hidden)
      .navigationTitle(L10n.text("fmdx.user_presets.manual_sheet_title"))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            manualPresetError = nil
            isManualPresetSheetPresented = false
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            saveManualPreset()
          }
        }
      }
      .appScreenBackground()
    }
  }

  private var frequencyEntrySheet: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Set Frequency")
        .font(.headline)

      TextField(frequencyInputPlaceholderText, text: $frequencyInputDraft)
        .keyboardType(.decimalPad)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .textFieldStyle(.roundedBorder)
        .focused($isFrequencyInputFocused)
        .submitLabel(.done)
        .onSubmit {
          applyExactFrequencyInput()
        }
        .accessibilityLabel(L10n.text("Frequency input"))
        .accessibilityHint(frequencyInputHintText)

      Text(frequencyInputHintText)
        .font(.footnote)
        .foregroundStyle(.secondary)

      if let frequencyInputError {
        Text(frequencyInputError)
          .foregroundStyle(.red)
          .font(.footnote)
          .accessibilityLabel(L10n.text("Frequency input error"))
          .accessibilityValue(frequencyInputError)
      }

      Spacer(minLength: 0)

      HStack(spacing: 12) {
        Button("Cancel") {
          frequencyInputError = nil
          isFrequencyEntrySheetPresented = false
        }
        .buttonStyle(.bordered)

        Button("Apply") {
          applyExactFrequencyInput()
        }
        .buttonStyle(.borderedProminent)
      }
      .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .padding()
    .onAppear {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        isFrequencyInputFocused = true
      }
    }
    .onDisappear {
      isFrequencyInputFocused = false
    }
    .appScreenBackground()
  }

  private func beginSavingCurrentFrequency() {
    presetNameDraft = presetStore.defaultName(
      for: radioSession.settings.frequencyHz,
      mode: radioSession.settings.mode
    )
    isSavePresetSheetPresented = true
  }

  private func beginManualPresetEntry(for profile: SDRConnectionProfile) {
    manualPresetNameDraft = ""
    manualPresetFrequencyDraft = FrequencyFormatter.fmDxEntryText(fromHz: radioSession.settings.frequencyHz)
    manualPresetModeDraft = availableModes(for: profile.backend).contains(radioSession.settings.mode)
      ? radioSession.settings.mode
      : .fm
    manualPresetError = nil
    isManualPresetSheetPresented = true
  }

  private func saveCurrentFrequencyAsPreset() {
    guard let profile = profileStore.selectedProfile else {
      isSavePresetSheetPresented = false
      return
    }

    presetStore.addPreset(
      name: presetNameDraft,
      frequencyHz: radioSession.settings.frequencyHz,
      mode: radioSession.settings.mode,
      profileID: profile.id,
      profileName: profile.name
    )
    isSavePresetSheetPresented = false
  }

  private func saveManualPreset() {
    guard let profile = profileStore.selectedProfile else {
      isManualPresetSheetPresented = false
      return
    }

    let parserContext: FrequencyInputParser.Context = {
      switch profile.backend {
      case .fmDxWebserver:
        return .fmBroadcast
      case .kiwiSDR:
        return .shortwave
      case .openWebRX:
        return .generic
      }
    }()

    guard let frequencyHz = FrequencyInputParser.parseHz(from: manualPresetFrequencyDraft, context: parserContext) else {
      manualPresetError = profile.backend == .fmDxWebserver
        ? L10n.text("frequency_input.invalid_fm")
        : L10n.text("frequency_input.invalid_generic")
      return
    }

    let allowedRange = frequencyRange(for: profile.backend)
    guard allowedRange.contains(frequencyHz) else {
      manualPresetError = profile.backend == .fmDxWebserver
        ? L10n.text("frequency_input.fmdx_range")
        : L10n.text("frequency_input.invalid_generic")
      return
    }

    let normalizedFrequencyHz = normalizeFrequencyHz(frequencyHz, for: profile.backend)
    let allowedModes = availableModes(for: profile.backend)
    let resolvedMode = allowedModes.contains(manualPresetModeDraft)
      ? manualPresetModeDraft
      : (allowedModes.first ?? .fm)

    presetStore.addPreset(
      name: manualPresetNameDraft,
      frequencyHz: normalizedFrequencyHz,
      mode: resolvedMode,
      profileID: profile.id,
      profileName: profile.name
    )

    manualPresetError = nil
    isManualPresetSheetPresented = false
  }

  private func importFMDXPluginPresets(from profile: SDRConnectionProfile, automatic: Bool = false) {
    guard profile.backend == .fmDxWebserver else { return }
    guard isImportingFMDXPresets == false else { return }

    isImportingFMDXPresets = true
    if !automatic {
      fmdxPresetImportStatusText = nil
    }

    Task {
      do {
        let importedPresets = try await FMDXPluginPresetImporter.fetchPresets(from: profile)
        await MainActor.run {
          var existingKeys = Set(
            visiblePresets(for: profile).map { "\($0.frequencyHz)|\($0.mode.rawValue)" }
          )
          var addedCount = 0

          for importedPreset in importedPresets {
            let key = "\(importedPreset.frequencyHz)|\(importedPreset.mode.rawValue)"
            guard existingKeys.contains(key) == false else { continue }

            presetStore.addPreset(
              name: importedPreset.name,
              frequencyHz: importedPreset.frequencyHz,
              mode: importedPreset.mode,
              profileID: profile.id,
              profileName: profile.name
            )
            existingKeys.insert(key)
            addedCount += 1
          }

          if automatic {
            if addedCount > 0 {
              fmdxPresetImportStatusText = L10n.text("fmdx.user_presets.imported_count", addedCount)
            }
          } else {
            if importedPresets.isEmpty {
              fmdxPresetImportStatusText = L10n.text("fmdx.user_presets.imported_none")
            } else if addedCount == 0 {
              fmdxPresetImportStatusText = L10n.text("fmdx.user_presets.imported_already")
            } else {
              fmdxPresetImportStatusText = L10n.text("fmdx.user_presets.imported_count", addedCount)
            }
          }

          isImportingFMDXPresets = false
        }
      } catch {
        await MainActor.run {
          if !automatic {
            fmdxPresetImportStatusText = L10n.text("fmdx.user_presets.import_error", error.localizedDescription)
          }
          isImportingFMDXPresets = false
        }
      }
    }
  }

  private func autoImportFMDXPluginPresetsIfNeeded(for profile: SDRConnectionProfile) {
    guard profile.backend == .fmDxWebserver else { return }
    guard autoImportedFMDXProfileIDs.contains(profile.id) == false else { return }
    autoImportedFMDXProfileIDs.insert(profile.id)
    importFMDXPluginPresets(from: profile, automatic: true)
  }

  private func saveBookmarkAsPreset(_ bookmark: SDRServerBookmark, profile: SDRConnectionProfile) {
    presetStore.addPreset(
      name: bookmark.name,
      frequencyHz: bookmark.frequencyHz,
      mode: bookmark.modulation ?? radioSession.settings.mode,
      profileID: profile.id,
      profileName: profile.name
    )
  }

  private func apply(preset: FrequencyPreset) {
    radioSession.setMode(preset.mode)
    let normalizedFrequencyHz = normalizeFrequencyHz(preset.frequencyHz, for: profileStore.selectedProfile?.backend)
    radioSession.setFrequencyHz(normalizedFrequencyHz)
  }

  private func beginFrequencyEntry() {
    let backend = profileStore.selectedProfile?.backend
    frequencyInputHintText = frequencyInputHint(for: backend)
    frequencyInputPlaceholderText = frequencyInputPlaceholder(for: backend)

    if backend == .fmDxWebserver {
      frequencyInputDraft = FrequencyFormatter.fmDxEntryText(fromHz: radioSession.settings.frequencyHz)
    } else {
      frequencyInputDraft = FrequencyFormatter.mhzText(fromHz: radioSession.settings.frequencyHz)
        .replacingOccurrences(of: " MHz", with: "")
    }
    frequencyInputError = nil
    isFrequencyInputFocused = false
    isFrequencyEntrySheetPresented = true
  }

  private func applyExactFrequencyInput() {
    let parserContext: FrequencyInputParser.Context = {
      switch profileStore.selectedProfile?.backend {
      case .fmDxWebserver:
        return .fmBroadcast
      case .kiwiSDR:
        return .shortwave
      case .openWebRX, .none:
        return .generic
      }
    }()

    guard let frequencyHz = FrequencyInputParser.parseHz(from: frequencyInputDraft, context: parserContext) else {
      frequencyInputError = profileStore.selectedProfile?.backend == .fmDxWebserver
        ? L10n.text("frequency_input.invalid_fm")
        : L10n.text("frequency_input.invalid_generic")
      return
    }

    if profileStore.selectedProfile?.backend == .fmDxWebserver &&
      !fmDxFrequencyRangeHz.contains(frequencyHz) {
      frequencyInputError = L10n.text("frequency_input.fmdx_range")
      return
    }

    let normalizedFrequencyHz = normalizeFrequencyHz(frequencyHz, for: profileStore.selectedProfile?.backend)
    radioSession.setFrequencyHz(normalizedFrequencyHz)
    frequencyInputError = nil
    isFrequencyEntrySheetPresented = false
  }

  private func frequencyHz(fromMHz value: Double) -> Int {
    let hz = Int((value * 1_000_000.0).rounded())
    if profileStore.selectedProfile?.backend == .fmDxWebserver {
      let rounded = Int((Double(hz) / 1_000.0).rounded()) * 1_000
      return min(max(rounded, fmDxFrequencyRangeHz.lowerBound), fmDxFrequencyRangeHz.upperBound)
    }
    return hz
  }

  private func saveAFAsPreset(_ frequencyHz: Int, profile: SDRConnectionProfile) {
    let name = L10n.text("fmdx.af_preset_name", FrequencyFormatter.mhzText(fromHz: frequencyHz))
    presetStore.addPreset(
      name: name,
      frequencyHz: frequencyHz,
      mode: .fm,
      profileID: profile.id,
      profileName: profile.name
    )
  }

  private func addQuickScanChannel(frequencyHz: Int) {
    let normalizedHz = normalizeFrequencyHz(frequencyHz, for: profileStore.selectedProfile?.backend)
    let id = "quick|\(normalizedHz)"
    guard quickScanChannels.contains(where: { $0.id == id }) == false else { return }

    let channel = ScanChannel(
      id: id,
      name: L10n.text("fmdx.af_scan_name", FrequencyFormatter.mhzText(fromHz: normalizedHz)),
      frequencyHz: normalizedHz,
      mode: .fm
    )
    quickScanChannels.append(channel)
    quickScanChannels.sort { $0.frequencyHz < $1.frequencyHz }
  }

  private func msDisplayText(_ ms: Int) -> String {
    switch ms {
    case 1:
      return L10n.text("common.yes")
    case 0:
      return L10n.text("common.no")
    default:
      return L10n.text("common.not_selected")
    }
  }

  private func ptyDisplayText(pty: Int, rbds: Bool?) -> String {
    let labelsEU = [
      "No PTY", "News", "Current Affairs", "Info", "Sport", "Education", "Drama", "Culture",
      "Science", "Varied", "Pop Music", "Rock Music", "Easy Listening", "Light Classical",
      "Serious Classical", "Other Music", "Weather", "Finance", "Children's", "Social Affairs",
      "Religion", "Phone-in", "Travel", "Leisure", "Jazz Music", "Country Music", "National Music",
      "Oldies Music", "Folk Music", "Documentary", "Alarm Test", "Alarm"
    ]
    let labelsUS = [
      "No PTY", "News", "Information", "Sports", "Talk", "Rock", "Classic Rock", "Adult Hits",
      "Soft Rock", "Top 40", "Country", "Oldies", "Soft Music", "Nostalgia", "Jazz", "Classical",
      "Rhythm and Blues", "Soft R&B", "Language", "Religious Music", "Religious Talk", "Personality",
      "Public", "College", "Spanish Talk", "Spanish Music", "Hip Hop", "", "", "Weather",
      "Emergency Test", "Emergency"
    ]

    let table = (rbds ?? false) ? labelsUS : labelsEU
    if pty >= 0 && pty < table.count {
      let label = table[pty].trimmingCharacters(in: .whitespacesAndNewlines)
      if !label.isEmpty {
        return "\(pty) (\(label))"
      }
    }
    return "\(pty)"
  }

  private func frequencyText(fromHz value: Int, backend: SDRBackend?) -> String {
    if backend == .fmDxWebserver {
      return FrequencyFormatter.fmDxMHzText(fromHz: value)
    }
    return FrequencyFormatter.mhzText(fromHz: value)
  }

  private func frequencyInputHint(for backend: SDRBackend?) -> String {
    if backend == .fmDxWebserver {
      return L10n.text("frequency_input.hint_fmdx")
    }
    return L10n.text("frequency_input.hint_generic")
  }

  private func frequencyInputPlaceholder(for backend: SDRBackend?) -> String {
    if backend == .fmDxWebserver {
      return L10n.text("frequency_input.placeholder_fmdx")
    }
    return L10n.text("frequency_input.placeholder_generic")
  }

  private func frequencyRange(for backend: SDRBackend) -> ClosedRange<Int> {
    switch backend {
    case .fmDxWebserver:
      return fmDxFrequencyRangeHz
    case .kiwiSDR:
      return kiwiFrequencyRangeHz
    case .openWebRX:
      return defaultFrequencyRangeHz
    }
  }

  private func activeOpenWebRXBandName() -> String? {
    let frequency = radioSession.settings.frequencyHz
    return radioSession.openWebRXBandPlan.first(where: { $0.lowerBoundHz...$0.upperBoundHz ~= frequency })?.name
  }

  private func normalizeFrequencyHz(_ value: Int, for backend: SDRBackend?) -> Int {
    guard let backend else { return value }
    let range = frequencyRange(for: backend)
    return min(max(value, range.lowerBound), range.upperBound)
  }

  private func visiblePresets(for profile: SDRConnectionProfile) -> [FrequencyPreset] {
    presetStore.presets(for: profile.id)
  }

  private func scanChannels(
    for profile: SDRConnectionProfile,
    presets: [FrequencyPreset]
  ) -> [ScanChannel] {
    let channels: [ScanChannel]
    switch scanSource {
    case .favorites:
      channels = presets.map { preset in
        ScanChannel(
          id: "preset|\(preset.id.uuidString)",
          name: preset.name,
          frequencyHz: preset.frequencyHz,
          mode: preset.mode
        )
      }
    case .serverBookmarks:
      channels = radioSession.serverBookmarks.map { bookmark in
        ScanChannel(
          id: "bookmark|\(bookmark.id)",
          name: bookmark.name,
          frequencyHz: bookmark.frequencyHz,
          mode: bookmark.modulation
        )
      }
    case .quickList:
      channels = quickScanChannels
    }

    guard profile.backend == .fmDxWebserver else {
      return channels
    }

    let normalized = normalizeFMDXScanChannels(channels)
    if scanSource == .favorites, normalized.isEmpty {
      // For FM-DX, make scanner usable immediately even with empty favorites.
      return defaultFMDXScanChannels()
    }
    return normalized
  }

  private func normalizeFMDXScanChannels(_ channels: [ScanChannel]) -> [ScanChannel] {
    var normalized: [ScanChannel] = []
    normalized.reserveCapacity(channels.count)
    var seenFrequencies = Set<Int>()

    for channel in channels {
      let roundedHz = Int((Double(channel.frequencyHz) / 1_000.0).rounded()) * 1_000
      guard fmDxFrequencyRangeHz.contains(roundedHz) else { continue }
      guard seenFrequencies.insert(roundedHz).inserted else { continue }

      let trimmedName = channel.name.trimmingCharacters(in: .whitespacesAndNewlines)
      let displayName = trimmedName.isEmpty ? FrequencyFormatter.fmDxMHzText(fromHz: roundedHz) : trimmedName

      normalized.append(
        ScanChannel(
          id: "fmdx|\(roundedHz)",
          name: displayName,
          frequencyHz: roundedHz,
          mode: .fm
        )
      )
    }

    return normalized.sorted { $0.frequencyHz < $1.frequencyHz }
  }

  private func defaultFMDXScanChannels() -> [ScanChannel] {
    var generated: [ScanChannel] = []
    var frequencyHz = fmDxFrequencyRangeHz.lowerBound

    while frequencyHz <= fmDxFrequencyRangeHz.upperBound {
      generated.append(
        ScanChannel(
          id: "fmdx-auto|\(frequencyHz)",
          name: FrequencyFormatter.fmDxMHzText(fromHz: frequencyHz),
          frequencyHz: frequencyHz,
          mode: .fm
        )
      )
      frequencyHz += fmDxScannerAutoStepHz
    }

    return generated
  }
}

private struct ImportedFMDXPreset {
  let name: String
  let frequencyHz: Int
  let mode: DemodulationMode
}

private enum FMDXPluginPresetImporter {
  private static let minFMHz = 64_000_000
  private static let maxFMHz = 110_000_000

  static func fetchPresets(from profile: SDRConnectionProfile) async throws -> [ImportedFMDXPreset] {
    let indexURL = try makeIndexURL(from: profile)
    let html = try await fetchText(from: indexURL)

    guard let scriptURL = resolvePluginScriptURL(from: html, relativeTo: indexURL) else {
      throw SDRClientError.unsupported("Station list plugin was not found on this FM-DX server.")
    }

    let script = try await fetchText(from: scriptURL)
    let presets = parseDefaultPresetData(from: script)
    if presets.isEmpty {
      throw SDRClientError.unsupported("No station entries were found in plugin data.")
    }
    return presets
  }

  private static func makeIndexURL(from profile: SDRConnectionProfile) throws -> URL {
    let host = profile.host.trimmingCharacters(in: .whitespacesAndNewlines)
    guard host.isEmpty == false else {
      throw SDRClientError.invalidHost
    }
    guard (1...65535).contains(profile.port) else {
      throw SDRClientError.invalidPort
    }

    var components = URLComponents()
    components.scheme = profile.useTLS ? "https" : "http"
    components.host = host
    components.port = profile.port
    let normalizedPath = profile.normalizedPath.hasSuffix("/") ? profile.normalizedPath : "\(profile.normalizedPath)/"
    components.path = normalizedPath

    guard let url = components.url else {
      throw SDRClientError.invalidURL
    }
    return url
  }

  private static func fetchText(from url: URL) async throws -> String {
    let (data, response) = try await URLSession.shared.data(from: url)
    if let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode) == false {
      throw SDRClientError.unsupported("Server returned HTTP \(httpResponse.statusCode) for \(url.absoluteString)")
    }

    if let text = String(data: data, encoding: .utf8), text.isEmpty == false {
      return text
    }
    if let text = String(data: data, encoding: .isoLatin1), text.isEmpty == false {
      return text
    }

    throw SDRClientError.unsupported("Unable to decode server response.")
  }

  private static func resolvePluginScriptURL(from html: String, relativeTo baseURL: URL) -> URL? {
    if let src = firstMatch(
      pattern: "<script[^>]+src=[\"']([^\"']*pluginButtonPresets[^\"']*)[\"'][^>]*>",
      in: html,
      options: [.caseInsensitive]
    ) {
      return URL(string: src, relativeTo: baseURL)?.absoluteURL
    }

    if let src = firstMatch(
      pattern: "<script[^>]+src=[\"']([^\"']*preset[^\"']*\\.js[^\"']*)[\"'][^>]*>",
      in: html,
      options: [.caseInsensitive]
    ) {
      return URL(string: src, relativeTo: baseURL)?.absoluteURL
    }

    return nil
  }

  private static func parseDefaultPresetData(from script: String) -> [ImportedFMDXPreset] {
    let block = firstMatch(
      pattern: "defaultPresetData\\s*=\\s*\\{([\\s\\S]*?)\\}",
      in: script,
      options: [.dotMatchesLineSeparators]
    )
    guard let block else { return [] }

    guard let rawValues = firstMatch(
      pattern: "values\\s*:\\s*\\[([\\s\\S]*?)\\]",
      in: block,
      options: [.dotMatchesLineSeparators]
    ) else {
      return []
    }

    let rawNames =
      firstMatch(
        pattern: "names\\s*:\\s*\\[([\\s\\S]*?)\\]",
        in: block,
        options: [.dotMatchesLineSeparators]
      )
      ?? firstMatch(
        pattern: "ps\\s*:\\s*\\[([\\s\\S]*?)\\]",
        in: block,
        options: [.dotMatchesLineSeparators]
      )
      ?? ""

    let valuesMHz = parseDoubleArray(rawValues)
    let names = parseStringArray(rawNames)

    var presets: [ImportedFMDXPreset] = []
    presets.reserveCapacity(valuesMHz.count)
    var seenFrequencies = Set<Int>()

    for (index, valueMHz) in valuesMHz.enumerated() {
      guard valueMHz.isFinite, valueMHz > 0 else { continue }
      let frequencyHz = normalizeFrequencyHz(fromMHz: valueMHz)
      guard seenFrequencies.insert(frequencyHz).inserted else { continue }

      let fallbackName = FrequencyFormatter.fmDxMHzText(fromHz: frequencyHz)
      let name = index < names.count
        ? sanitizedName(names[index], fallback: fallbackName)
        : fallbackName

      presets.append(
        ImportedFMDXPreset(
          name: name,
          frequencyHz: frequencyHz,
          mode: .fm
        )
      )
    }

    return presets
  }

  private static func parseDoubleArray(_ raw: String) -> [Double] {
    captureAll(
      pattern: "-?\\d+(?:\\.\\d+)?",
      in: raw
    )
    .compactMap { Double($0) }
  }

  private static func parseStringArray(_ raw: String) -> [String] {
    var results: [String] = []
    var buffer = ""
    var activeQuote: Character?
    var isEscaped = false

    for character in raw {
      if let quote = activeQuote {
        if isEscaped {
          buffer.append(character)
          isEscaped = false
          continue
        }

        if character == "\\" {
          isEscaped = true
          continue
        }

        if character == quote {
          let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
          if value.isEmpty == false {
            results.append(value)
          }
          buffer = ""
          activeQuote = nil
          continue
        }

        buffer.append(character)
        continue
      }

      if character == "'" || character == "\"" {
        activeQuote = character
        buffer = ""
      }
    }

    return results
  }

  private static func normalizeFrequencyHz(fromMHz value: Double) -> Int {
    let hz = Int((value * 1_000_000.0).rounded())
    let roundedToKHz = Int((Double(hz) / 1_000.0).rounded()) * 1_000
    return min(max(roundedToKHz, minFMHz), maxFMHz)
  }

  private static func sanitizedName(_ value: String, fallback: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
  }

  private static func firstMatch(
    pattern: String,
    in text: String,
    options: NSRegularExpression.Options = []
  ) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
      return nil
    }

    let nsText = text as NSString
    let range = NSRange(location: 0, length: nsText.length)
    guard let match = regex.firstMatch(in: text, options: [], range: range),
      match.numberOfRanges > 1 else {
      return nil
    }

    let captureRange = match.range(at: 1)
    guard captureRange.location != NSNotFound else {
      return nil
    }
    return nsText.substring(with: captureRange)
  }

  private static func captureAll(
    pattern: String,
    in text: String
  ) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
      return []
    }

    let nsText = text as NSString
    let range = NSRange(location: 0, length: nsText.length)
    let matches = regex.matches(in: text, options: [], range: range)

    return matches.compactMap { match in
      if match.numberOfRanges > 2 {
        let first = match.range(at: 1)
        if first.location != NSNotFound {
          return nsText.substring(with: first)
        }
        let second = match.range(at: 2)
        if second.location != NSNotFound {
          return nsText.substring(with: second)
        }
      }
      if match.numberOfRanges > 1 {
        let capture = match.range(at: 1)
        if capture.location != NSNotFound {
          return nsText.substring(with: capture)
        }
      }
      return nsText.substring(with: match.range)
    }
  }
}

struct WaterfallStripView: View {
  let bins: [UInt8]

  var body: some View {
    GeometryReader { geometry in
      Canvas { context, size in
        guard !bins.isEmpty else { return }
        let count = bins.count
        let stripeWidth = max(1, size.width / CGFloat(count))

        for (index, value) in bins.enumerated() {
          let normalized = Double(value) / 255.0
          let color = Color(
            hue: 0.65 - (0.65 * normalized),
            saturation: 0.9,
            brightness: 0.25 + (0.75 * normalized)
          )
          let x = CGFloat(index) * stripeWidth
          let rect = CGRect(x: x, y: 0, width: stripeWidth + 0.5, height: size.height)
          context.fill(Path(rect), with: .color(color))
        }
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
    }
  }
}
