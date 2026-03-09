import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var profileStore: ProfileStore
  @EnvironmentObject private var radioSession: RadioSessionViewModel

  private let fmDxFMTuneStepOptionsHz: [Int] = [25_000, 50_000, 100_000, 200_000]
  private let fmDxAMTuneStepOptionsHz: [Int] = [9_000, 10_000, 25_000, 50_000]

  var body: some View {
    TabView {
      ReceiverView()
        .tabItem {
          Label("Receiver", systemImage: "dial.high")
        }

      RadiosView()
        .tabItem {
          Label("Radios", systemImage: "dot.radiowaves.left.and.right")
        }

      SettingsView()
        .tabItem {
          Label("Settings", systemImage: "gearshape")
        }
    }
    .tint(AppTheme.tint)
    .toolbarBackground(.regularMaterial, for: .tabBar)
    .toolbarBackground(.visible, for: .tabBar)
    .background(globalVoiceOverRotorBridge())
    .appScreenBackground()
  }

  @ViewBuilder
  private func globalVoiceOverRotorBridge() -> some View {
    let backend = profileStore.selectedProfile?.backend
    let isEnabled = backend != nil

    GlobalVoiceOverRotorBridge(
      isEnabled: isEnabled,
      frequencyRotorName: L10n.text("receiver.voiceover_rotor.frequency"),
      tuneStepRotorName: L10n.text("receiver.voiceover_rotor.tune_step"),
      onTuneIncrement: {
        guard let backend else { return }
        radioSession.tune(byStepCount: 1)
        announceFrequency(for: backend)
      },
      onTuneDecrement: {
        guard let backend else { return }
        radioSession.tune(byStepCount: -1)
        announceFrequency(for: backend)
      },
      onStepIncrement: {
        guard let backend else { return }
        cycleTuneStep(by: 1, backend: backend)
      },
      onStepDecrement: {
        guard let backend else { return }
        cycleTuneStep(by: -1, backend: backend)
      }
    )
    .frame(width: 0, height: 0)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func cycleTuneStep(by offset: Int, backend: SDRBackend) {
    let steps = tuneStepOptions(for: backend)
    guard !steps.isEmpty else { return }

    let currentStep = radioSession.settings.tuneStepHz
    let currentIndex: Int
    if let exactIndex = steps.firstIndex(of: currentStep) {
      currentIndex = exactIndex
    } else {
      currentIndex = steps.enumerated().min(by: {
        abs($0.element - currentStep) < abs($1.element - currentStep)
      })?.offset ?? 0
    }

    let nextIndex = min(max(currentIndex + offset, 0), steps.count - 1)
    guard nextIndex != currentIndex else { return }

    radioSession.setTuneStepHz(steps[nextIndex])
    let stepText = FrequencyFormatter.tuneStepText(fromHz: radioSession.settings.tuneStepHz)
    UIAccessibility.post(
      notification: .announcement,
      argument: L10n.text("receiver.tune_step.changed", stepText)
    )
  }

  private func tuneStepOptions(for backend: SDRBackend) -> [Int] {
    switch backend {
    case .fmDxWebserver:
      return radioSession.settings.mode == .am ? fmDxAMTuneStepOptionsHz : fmDxFMTuneStepOptionsHz
    case .kiwiSDR, .openWebRX:
      return RadioSessionSettings.supportedTuneStepsHz
    }
  }

  private func announceFrequency(for backend: SDRBackend) {
    let value = radioSession.settings.frequencyHz
    let announcement: String

    switch backend {
    case .fmDxWebserver:
      announcement = FrequencyFormatter.fmDxMHzText(fromHz: value)
    case .kiwiSDR, .openWebRX:
      if value < 1_000_000 {
        let kilohertz = Int((Double(value) / 1_000.0).rounded())
        announcement = "\(kilohertz) kHz"
      } else {
        announcement = FrequencyFormatter.mhzText(fromHz: value)
      }
    }

    UIAccessibility.post(notification: .announcement, argument: announcement)
  }
}
