import SwiftUI

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
  @State private var isFrequencyEntrySheetPresented = false
  @State private var presetNameDraft = ""
  @State private var frequencyInputDraft = ""
  @State private var frequencyInputError: String?
  @State private var scanSource: ScanSource = .favorites
  @State private var quickScanChannels: [ScanChannel] = []
  @State private var scannerDwellSeconds: Double = 1.5
  @State private var scannerHoldSeconds: Double = 4.0

  private let defaultFrequencyRangeHz: ClosedRange<Int> = 100_000...3_000_000_000
  private let fmDxFrequencyRangeHz: ClosedRange<Int> = 64_000_000...110_000_000
  private let fmDxTuneStepOptionsHz: [Int] = [50_000, 100_000, 200_000]

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
      .sheet(isPresented: $isFrequencyEntrySheetPresented) {
        frequencyEntrySheet
      }
      .appScreenBackground()
    }
  }

  @ViewBuilder
  private func receiverForm(for profile: SDRConnectionProfile) -> some View {
    let presets = visiblePresets(for: profile)
    let scannerChannels = scanChannels(for: profile, presets: presets)

    Form {
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

        if profile.backend == .openWebRX && radioSession.state == .connected &&
          radioSession.connectedProfileID == profile.id {
          if radioSession.openWebRXProfiles.isEmpty {
            Text("Waiting for OpenWebRX profile list...")
              .foregroundStyle(.secondary)
          } else {
            Picker(
              "Server profile",
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

      Section("Tuning") {
        Stepper(
          value: Binding(
            get: { radioSession.settings.frequencyHz },
            set: { radioSession.setFrequencyHz($0) }
          ),
          in: frequencyRange(for: profile.backend),
          step: radioSession.settings.tuneStepHz
        ) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Frequency")
            Text(
              frequencyText(
                fromHz: radioSession.settings.frequencyHz,
                backend: profile.backend
              )
            )
              .foregroundStyle(.secondary)
              .accessibilityHidden(true)
          }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Frequency")
        .accessibilityValue(
          frequencyText(
            fromHz: radioSession.settings.frequencyHz,
            backend: profile.backend
          )
        )
        .accessibilityHint(
          L10n.text(
            "receiver.frequency.swipe_hint",
            FrequencyFormatter.tuneStepText(fromHz: radioSession.settings.tuneStepHz)
          )
        )

        HStack {
          Button {
            radioSession.tune(byStepCount: -1)
          } label: {
            Label("Step down", systemImage: "minus.circle")
          }
          .accessibilityLabel(L10n.text("Tune down"))
          .accessibilityValue(FrequencyFormatter.tuneStepText(fromHz: radioSession.settings.tuneStepHz))
          .accessibilityHint(L10n.text("Decrease frequency by selected step size"))

          Spacer()

          Button {
            radioSession.tune(byStepCount: 1)
          } label: {
            Label("Step up", systemImage: "plus.circle")
          }
          .accessibilityLabel(L10n.text("Tune up"))
          .accessibilityValue(FrequencyFormatter.tuneStepText(fromHz: radioSession.settings.tuneStepHz))
          .accessibilityHint(L10n.text("Increase frequency by selected step size"))
        }

        Button {
          beginFrequencyEntry()
        } label: {
          Label("Set exact frequency", systemImage: "number")
        }
        .accessibilityHint(L10n.text("Enter frequency in hertz, kilohertz or megahertz"))

        Picker(
          "Tune step",
          selection: Binding(
            get: { radioSession.settings.tuneStepHz },
            set: { radioSession.setTuneStepHz($0) }
          )
        ) {
          ForEach(tuneStepOptions(for: profile.backend), id: \.self) { stepHz in
            Text(FrequencyFormatter.tuneStepText(fromHz: stepHz)).tag(stepHz)
          }
        }
        .accessibilityLabel("Tune step")
        .accessibilityValue(FrequencyFormatter.tuneStepText(fromHz: radioSession.settings.tuneStepHz))

        Picker(
          "Mode",
          selection: Binding(
            get: { radioSession.settings.mode },
            set: { radioSession.setMode($0) }
          )
        ) {
          ForEach(DemodulationMode.allCases) { mode in
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
      }
      .appSectionStyle()

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

      if profile.backend == .fmDxWebserver {
        Section(L10n.text("fmdx.controls")) {
          let forcedStereoEnabled = radioSession.fmdxTelemetry?.isForcedStereo ?? false
          Button {
            radioSession.setFMDXForcedStereoEnabled(!forcedStereoEnabled)
          } label: {
            LabeledContent(
              L10n.text("fmdx.audio_mode"),
              value: fmdxAudioModeButtonValue(for: radioSession.fmdxTelemetry)
            )
          }
          .disabled(radioSession.state != .connected)
          .accessibilityLabel(L10n.text("fmdx.audio_mode"))
          .accessibilityValue(fmdxAudioModeButtonValue(for: radioSession.fmdxTelemetry))

          if !radioSession.fmdxCapabilities.antennas.isEmpty {
            Picker(
              L10n.text("fmdx.antenna"),
              selection: Binding(
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
            ) {
              ForEach(radioSession.fmdxCapabilities.antennas) { option in
                Text(option.label).tag(option.id)
              }
            }
            .disabled(radioSession.state != .connected)
          }

          if !radioSession.fmdxCapabilities.bandwidths.isEmpty {
            Picker(
              L10n.text("fmdx.bandwidth"),
              selection: Binding(
                get: {
                  radioSession.selectedFMDXBandwidthID
                    ?? radioSession.fmdxCapabilities.bandwidths.first?.id
                    ?? ""
                },
                set: { value in
                  guard
                    let option = radioSession.fmdxCapabilities.bandwidths.first(where: { $0.id == value })
                  else { return }
                  radioSession.setFMDXBandwidth(option)
                }
              )
            ) {
              ForEach(radioSession.fmdxCapabilities.bandwidths) { option in
                Text(option.label).tag(option.id)
              }
            }
            .disabled(radioSession.state != .connected)
          }
        }
        .appSectionStyle()
      }

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

      if profile.backend == .fmDxWebserver, let telemetry = radioSession.fmdxTelemetry {
        Section("FM-DX Live") {
          if let frequencyMHz = telemetry.frequencyMHz {
            LabeledContent("Frequency", value: FrequencyFormatter.fmDxMHzText(fromMHz: frequencyMHz))
          }
          if let signal = telemetry.signal {
            LabeledContent("Signal", value: String(format: "%.1f dBf", signal))
          }
          if let signalTop = telemetry.signalTop {
            LabeledContent("Signal peak", value: String(format: "%.1f dBf", signalTop))
          }
          if let users = telemetry.users {
            LabeledContent("Users", value: "\(users)")
          }
          if let isStereo = telemetry.isStereo {
            LabeledContent(
              L10n.text("fmdx.audio_state"),
              value: isStereo ? L10n.text("fmdx.stereo_state.stereo") : L10n.text("fmdx.stereo_state.mono")
            )
          }
          if let isForced = telemetry.isForcedStereo {
            LabeledContent(
              L10n.text("fmdx.audio_mode"),
              value: isForced ? L10n.text("fmdx.stereo_state.stereo") : L10n.text("fmdx.stereo_state.mono")
            )
          }
          if let pi = telemetry.pi, !pi.isEmpty {
            LabeledContent("PI", value: pi)
          }
          if let ps = telemetry.ps, !ps.isEmpty {
            LabeledContent("PS", value: ps)
          }
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
          if let countryName = telemetry.countryName, !countryName.isEmpty {
            LabeledContent("Country", value: countryName)
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
          if let errors = telemetry.psErrors, !errors.isEmpty {
            Text(L10n.text("fmdx.ps_errors", errors))
              .font(.footnote)
          }
          if let rt0 = telemetry.rt0, !rt0.isEmpty {
            Text(L10n.text("fmdx.rt0", rt0))
              .font(.footnote)
          }
          if let errors = telemetry.rt0Errors, !errors.isEmpty {
            Text(L10n.text("fmdx.rt0_errors", errors))
              .font(.footnote)
          }
          if let rt1 = telemetry.rt1, !rt1.isEmpty {
            Text(L10n.text("fmdx.rt1", rt1))
              .font(.footnote)
          }
          if let errors = telemetry.rt1Errors, !errors.isEmpty {
            Text(L10n.text("fmdx.rt1_errors", errors))
              .font(.footnote)
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
              LabeledContent("Distance", value: "\(distance) km")
            }
            if let azimuth = tx.azimuthDeg, !azimuth.isEmpty {
              LabeledContent("Azimuth", value: "\(azimuth) deg")
            }
            if let erp = tx.erpKW, !erp.isEmpty {
              LabeledContent("ERP", value: "\(erp) kW")
            }
            if let polarization = tx.polarization, !polarization.isEmpty {
              LabeledContent("Polarization", value: polarization)
            }
          }
        }
        .appSectionStyle()
      }

      if profile.backend == .kiwiSDR, let telemetry = radioSession.kiwiTelemetry {
        Section("Kiwi Live") {
          if let rssi = telemetry.rssiDBm {
            LabeledContent("S-meter", value: String(format: "%.1f dBm", rssi))
          } else {
            LabeledContent("S-meter", value: "No data")
          }
          LabeledContent("Audio rate", value: "\(telemetry.sampleRateHz) Hz")

          if !telemetry.waterfallBins.isEmpty {
            WaterfallStripView(bins: telemetry.waterfallBins)
              .frame(height: 88)
              .clipShape(RoundedRectangle(cornerRadius: 8))
              .overlay {
                RoundedRectangle(cornerRadius: 8)
                  .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
              }
              .accessibilityLabel("Waterfall")
              .accessibilityValue("Live spectrum strip")
          } else {
            Text("Waterfall loading...")
              .foregroundStyle(.secondary)
          }
        }
        .appSectionStyle()
      }

      Section("DSP") {
        if profile.backend == .fmDxWebserver {
          Toggle(
            "AGC",
            isOn: Binding(
              get: { radioSession.settings.agcEnabled },
              set: { radioSession.setAGCEnabled($0) }
            )
          )
          .accessibilityHint("Automatic gain control")

          Toggle(
            "cEQ",
            isOn: Binding(
              get: { radioSession.settings.noiseReductionEnabled },
              set: { radioSession.setNoiseReductionEnabled($0) }
            )
          )

          Toggle(
            "iMS",
            isOn: Binding(
              get: { radioSession.settings.imsEnabled },
              set: { radioSession.setIMSEnabled($0) }
            )
          )
        } else {
          Toggle(
            "AGC",
            isOn: Binding(
              get: { radioSession.settings.agcEnabled },
              set: { radioSession.setAGCEnabled($0) }
            )
          )
          .accessibilityHint("Automatic gain control")

          Toggle(
            "Noise reduction",
            isOn: Binding(
              get: { radioSession.settings.noiseReductionEnabled },
              set: { radioSession.setNoiseReductionEnabled($0) }
            )
          )

          Toggle(
            "Squelch",
            isOn: Binding(
              get: { radioSession.settings.squelchEnabled },
              set: { radioSession.setSquelchEnabled($0) }
            )
          )
        }

        Button("Reset DSP settings") {
          radioSession.resetDSPSettings()
        }
        .accessibilityHint(L10n.text("Restores demodulation mode and DSP controls to defaults"))
      }
      .appSectionStyle()

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
    .scrollContentBackground(.hidden)
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

  private func tuneStepOptions(for backend: SDRBackend) -> [Int] {
    switch backend {
    case .fmDxWebserver:
      return fmDxTuneStepOptionsHz
    case .kiwiSDR, .openWebRX:
      return RadioSessionSettings.supportedTuneStepsHz
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

  private var frequencyEntrySheet: some View {
    NavigationStack {
      Form {
        TextField(frequencyInputPlaceholder, text: $frequencyInputDraft)
          .keyboardType(.decimalPad)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .accessibilityLabel(L10n.text("Frequency input"))
          .accessibilityHint(frequencyInputHint)

        if let frequencyInputError {
          Text(frequencyInputError)
            .foregroundStyle(.red)
            .font(.footnote)
            .accessibilityLabel(L10n.text("Frequency input error"))
            .accessibilityValue(frequencyInputError)
        }

        LabeledContent(
          "Current",
          value: frequencyText(fromHz: radioSession.settings.frequencyHz, backend: profileStore.selectedProfile?.backend)
        )
      }
      .scrollContentBackground(.hidden)
      .navigationTitle("Set Frequency")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            frequencyInputError = nil
            isFrequencyEntrySheetPresented = false
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Apply") {
            applyExactFrequencyInput()
          }
        }
      }
      .appScreenBackground()
    }
  }

  private func beginSavingCurrentFrequency() {
    presetNameDraft = presetStore.defaultName(
      for: radioSession.settings.frequencyHz,
      mode: radioSession.settings.mode
    )
    isSavePresetSheetPresented = true
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
    if backend == .fmDxWebserver {
      frequencyInputDraft = FrequencyFormatter.fmDxEntryText(fromHz: radioSession.settings.frequencyHz)
    } else {
      frequencyInputDraft = FrequencyFormatter.mhzText(fromHz: radioSession.settings.frequencyHz)
        .replacingOccurrences(of: " MHz", with: "")
    }
    frequencyInputError = nil
    isFrequencyEntrySheetPresented = true
  }

  private func applyExactFrequencyInput() {
    let parserContext: FrequencyInputParser.Context =
      profileStore.selectedProfile?.backend == .fmDxWebserver ? .fmBroadcast : .generic

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

  private func fmdxAudioModeButtonValue(for telemetry: FMDXTelemetry?) -> String {
    let forcedStereoEnabled = telemetry?.isForcedStereo == true
    return forcedStereoEnabled ? L10n.text("fmdx.stereo_state.stereo") : L10n.text("fmdx.stereo_state.mono")
  }

  private func frequencyText(fromHz value: Int, backend: SDRBackend?) -> String {
    if backend == .fmDxWebserver {
      return FrequencyFormatter.fmDxMHzText(fromHz: value)
    }
    return FrequencyFormatter.mhzText(fromHz: value)
  }

  private var frequencyInputHint: String {
    if profileStore.selectedProfile?.backend == .fmDxWebserver {
      return L10n.text("frequency_input.hint_fmdx")
    }
    return L10n.text("frequency_input.hint_generic")
  }

  private var frequencyInputPlaceholder: String {
    if profileStore.selectedProfile?.backend == .fmDxWebserver {
      return L10n.text("frequency_input.placeholder_fmdx")
    }
    return L10n.text("frequency_input.placeholder_generic")
  }

  private func frequencyRange(for backend: SDRBackend) -> ClosedRange<Int> {
    switch backend {
    case .fmDxWebserver:
      return fmDxFrequencyRangeHz
    case .kiwiSDR, .openWebRX:
      return defaultFrequencyRangeHz
    }
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
    switch scanSource {
    case .favorites:
      return presets.map { preset in
        ScanChannel(
          id: "preset|\(preset.id.uuidString)",
          name: preset.name,
          frequencyHz: preset.frequencyHz,
          mode: preset.mode
        )
      }
    case .serverBookmarks:
      return radioSession.serverBookmarks.map { bookmark in
        ScanChannel(
          id: "bookmark|\(bookmark.id)",
          name: bookmark.name,
          frequencyHz: bookmark.frequencyHz,
          mode: bookmark.modulation
        )
      }
    case .quickList:
      return quickScanChannels
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
