import SwiftUI

private enum ScanSource: String, CaseIterable, Identifiable {
  case favorites
  case serverBookmarks

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .favorites:
      return "Favorites"
    case .serverBookmarks:
      return "Server list"
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
  @State private var scannerDwellSeconds: Double = 1.5
  @State private var scannerHoldSeconds: Double = 4.0

  private let minFrequencyHz = 100_000
  private let maxFrequencyHz = 3_000_000_000

  var body: some View {
    NavigationStack {
      Group {
        if let selectedProfile = profileStore.selectedProfile {
          receiverForm(for: selectedProfile)
        } else {
          UnavailableContentView(
            title: "No Selected Radio",
            systemImage: "antenna.radiowaves.left.and.right",
            description: "Add and select a receiver profile in the Radios tab."
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
    }
  }

  @ViewBuilder
  private func receiverForm(for profile: SDRConnectionProfile) -> some View {
    let presets = visiblePresets(for: profile)
    let scannerChannels = scanChannels(for: profile, presets: presets)

    Form {
      Section("Connection") {
        LabeledContent("Profile", value: profile.name)
          .accessibilityLabel("Selected profile")
          .accessibilityValue(profile.name)

        LabeledContent("Backend", value: profile.backend.displayName)
        LabeledContent("Endpoint", value: profile.endpointDescription)

        LabeledContent("Status", value: radioSession.statusText)
          .accessibilityLabel("Connection status")
          .accessibilityValue(radioSession.statusText)

        if let backendStatus = radioSession.backendStatusText, !backendStatus.isEmpty {
          LabeledContent("Receiver data", value: backendStatus)
            .accessibilityLabel("Receiver live data")
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
            .accessibilityHint("Select SDR profile from OpenWebRX server")
          }
        }

        if let error = radioSession.lastError {
          Text(error)
            .foregroundStyle(.red)
            .font(.footnote)
            .accessibilityLabel("Last error")
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
        .accessibilityHint("Double tap to change connection state")

        if radioSession.state == .failed {
          Button {
            radioSession.reconnect(to: profile)
          } label: {
            Text("Reconnect")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .accessibilityHint("Try connecting to this receiver again")
        }
      }

      Section("Tuning") {
        Stepper(
          value: Binding(
            get: { radioSession.settings.frequencyHz },
            set: { radioSession.setFrequencyHz($0) }
          ),
          in: minFrequencyHz...maxFrequencyHz,
          step: radioSession.settings.tuneStepHz
        ) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Frequency")
            Text(FrequencyFormatter.mhzText(fromHz: radioSession.settings.frequencyHz))
              .foregroundStyle(.secondary)
          }
        }
        .accessibilityLabel("Frequency")
        .accessibilityValue(FrequencyFormatter.mhzText(fromHz: radioSession.settings.frequencyHz))
        .accessibilityHint(
          "Swipe up or down to tune by \(FrequencyFormatter.tuneStepText(fromHz: radioSession.settings.tuneStepHz))"
        )

        HStack {
          Button {
            radioSession.tune(byStepCount: -1)
          } label: {
            Label("Step down", systemImage: "minus.circle")
          }
          .accessibilityLabel("Tune down")
          .accessibilityValue(FrequencyFormatter.tuneStepText(fromHz: radioSession.settings.tuneStepHz))
          .accessibilityHint("Decrease frequency by selected step size")

          Spacer()

          Button {
            radioSession.tune(byStepCount: 1)
          } label: {
            Label("Step up", systemImage: "plus.circle")
          }
          .accessibilityLabel("Tune up")
          .accessibilityValue(FrequencyFormatter.tuneStepText(fromHz: radioSession.settings.tuneStepHz))
          .accessibilityHint("Increase frequency by selected step size")
        }

        Button {
          beginFrequencyEntry()
        } label: {
          Label("Set exact frequency", systemImage: "number")
        }
        .accessibilityHint("Enter frequency in hertz, kilohertz or megahertz")

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

        VStack(alignment: .leading, spacing: 6) {
          Text("RF Gain: \(Int(radioSession.settings.rfGain))")
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
        .accessibilityLabel("RF gain")
        .accessibilityValue("\(Int(radioSession.settings.rfGain))")
      }

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
      }

      Section("Scanner") {
        Picker("Channel source", selection: $scanSource) {
          ForEach(ScanSource.allCases) { source in
            Text(source.displayName).tag(source)
          }
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

      if profile.backend == .fmDxWebserver, let telemetry = radioSession.fmdxTelemetry {
        Section("FM-DX Live") {
          if let frequencyMHz = telemetry.frequencyMHz {
            LabeledContent("Frequency", value: String(format: "%.3f MHz", frequencyMHz))
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
            LabeledContent("Stereo", value: isStereo ? "On" : "Off")
          }
          if let isForced = telemetry.isForcedStereo {
            LabeledContent("Forced stereo", value: isForced ? "On" : "Off")
          }
          if let pi = telemetry.pi, !pi.isEmpty {
            LabeledContent("PI", value: pi)
          }
          if let ps = telemetry.ps, !ps.isEmpty {
            LabeledContent("PS", value: ps)
          }
          if let pty = telemetry.pty {
            LabeledContent("PTY", value: "\(pty)")
          }
          if let tp = telemetry.tp {
            LabeledContent("TP", value: tp == 1 ? "Yes" : "No")
          }
          if let ta = telemetry.ta {
            LabeledContent("TA", value: ta == 1 ? "Yes" : "No")
          }
          if let countryName = telemetry.countryName, !countryName.isEmpty {
            LabeledContent("Country", value: countryName)
          }
          if let countryISO = telemetry.countryISO, !countryISO.isEmpty {
            LabeledContent("ISO", value: countryISO)
          }
          if !telemetry.afMHz.isEmpty {
            Text("AF: \(telemetry.afMHz.prefix(12).map { String(format: "%.1f", $0) }.joined(separator: ", "))")
              .font(.footnote)
          }
          if let rt0 = telemetry.rt0, !rt0.isEmpty {
            Text("RT0: \(rt0)")
              .font(.footnote)
          }
          if let rt1 = telemetry.rt1, !rt1.isEmpty {
            Text("RT1: \(rt1)")
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
      }

      Section("DSP") {
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

        Button("Reset DSP settings") {
          radioSession.resetDSPSettings()
        }
        .accessibilityHint("Restores demodulation mode and DSP controls to defaults")
      }

      Section("Favorites") {
        Button {
          beginSavingCurrentFrequency()
        } label: {
          Label("Save current frequency", systemImage: "star")
        }
        .accessibilityHint("Saves current frequency and mode as a favorite")

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
            .accessibilityHint("Double tap to apply this favorite")
          }
        }
      }

      Section("Audio") {
        VStack(alignment: .leading, spacing: 6) {
          Text("Volume: \(Int((radioSession.settings.audioVolume * 100).rounded()))%")
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
        .accessibilityLabel("Audio volume")
        .accessibilityValue("\(Int((radioSession.settings.audioVolume * 100).rounded())) percent")

        Toggle(
          "Mute audio",
          isOn: Binding(
            get: { radioSession.settings.audioMuted },
            set: { radioSession.setAudioMuted($0) }
          )
        )
      }
    }
  }

  private func connectionButtonTitle(for profile: SDRConnectionProfile) -> String {
    if radioSession.state == .connecting {
      return "Connecting..."
    }
    if radioSession.state == .connected &&
      radioSession.connectedProfileID == profile.id {
      return "Disconnect"
    }
    return "Connect"
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
      return RadioSessionSettings.supportedTuneStepsHz.filter { $0 >= 1_000 }
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
          .accessibilityLabel("Preset name")

        LabeledContent(
          "Frequency",
          value: FrequencyFormatter.mhzText(fromHz: radioSession.settings.frequencyHz)
        )
        LabeledContent("Mode", value: radioSession.settings.mode.displayName)
      }
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
    }
  }

  private var frequencyEntrySheet: some View {
    NavigationStack {
      Form {
        TextField("7.050 MHz or 7050 kHz", text: $frequencyInputDraft)
          .keyboardType(.decimalPad)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .accessibilityLabel("Frequency input")
          .accessibilityHint("Examples: seven point zero five megahertz or seven thousand fifty kilohertz")

        if let frequencyInputError {
          Text(frequencyInputError)
            .foregroundStyle(.red)
            .font(.footnote)
            .accessibilityLabel("Frequency input error")
            .accessibilityValue(frequencyInputError)
        }

        LabeledContent(
          "Current",
          value: FrequencyFormatter.mhzText(fromHz: radioSession.settings.frequencyHz)
        )
      }
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
    radioSession.setFrequencyHz(preset.frequencyHz)
  }

  private func beginFrequencyEntry() {
    frequencyInputDraft = FrequencyFormatter.mhzText(fromHz: radioSession.settings.frequencyHz)
      .replacingOccurrences(of: " MHz", with: "")
    frequencyInputError = nil
    isFrequencyEntrySheetPresented = true
  }

  private func applyExactFrequencyInput() {
    guard let frequencyHz = FrequencyInputParser.parseHz(from: frequencyInputDraft) else {
      frequencyInputError = "Invalid frequency. Use values like 7.050 MHz, 7050 kHz or 7050000."
      return
    }
    radioSession.setFrequencyHz(frequencyHz)
    frequencyInputError = nil
    isFrequencyEntrySheetPresented = false
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
