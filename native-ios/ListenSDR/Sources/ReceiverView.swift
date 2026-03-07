import SwiftUI

struct ReceiverView: View {
  @EnvironmentObject private var profileStore: ProfileStore
  @EnvironmentObject private var radioSession: RadioSessionViewModel
  @EnvironmentObject private var presetStore: FrequencyPresetStore
  @State private var isSavePresetSheetPresented = false
  @State private var presetNameDraft = ""

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
    }
  }

  @ViewBuilder
  private func receiverForm(for profile: SDRConnectionProfile) -> some View {
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

        Picker(
          "Tune step",
          selection: Binding(
            get: { radioSession.settings.tuneStepHz },
            set: { radioSession.setTuneStepHz($0) }
          )
        ) {
          ForEach(RadioSessionSettings.supportedTuneStepsHz, id: \.self) { stepHz in
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
      }

      Section("Favorites") {
        Button {
          beginSavingCurrentFrequency()
        } label: {
          Label("Save current frequency", systemImage: "star")
        }
        .accessibilityHint("Saves current frequency and mode as a favorite")

        if presetStore.presets.isEmpty {
          Text("No favorites yet. Save one to recall frequency and mode quickly.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(presetStore.presets) { preset in
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

  private func beginSavingCurrentFrequency() {
    presetNameDraft = presetStore.defaultName(
      for: radioSession.settings.frequencyHz,
      mode: radioSession.settings.mode
    )
    isSavePresetSheetPresented = true
  }

  private func saveCurrentFrequencyAsPreset() {
    presetStore.addPreset(
      name: presetNameDraft,
      frequencyHz: radioSession.settings.frequencyHz,
      mode: radioSession.settings.mode
    )
    isSavePresetSheetPresented = false
  }

  private func apply(preset: FrequencyPreset) {
    radioSession.setMode(preset.mode)
    radioSession.setFrequencyHz(preset.frequencyHz)
  }
}
