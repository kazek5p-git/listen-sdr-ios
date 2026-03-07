import SwiftUI

struct ReceiverView: View {
  @EnvironmentObject private var profileStore: ProfileStore
  @EnvironmentObject private var radioSession: RadioSessionViewModel

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
          in: 100_000...30_000_000,
          step: 100
        ) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Frequency")
            Text(FrequencyFormatter.mhzText(fromHz: radioSession.settings.frequencyHz))
              .foregroundStyle(.secondary)
          }
        }
        .accessibilityLabel("Frequency")
        .accessibilityValue(FrequencyFormatter.mhzText(fromHz: radioSession.settings.frequencyHz))
        .accessibilityHint("Swipe up or down to tune by one hundred hertz")

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
}
