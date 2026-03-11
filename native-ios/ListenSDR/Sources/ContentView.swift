import SwiftUI

struct ContentView: View {
  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject private var navigationState: AppNavigationState
  @EnvironmentObject private var profileStore: ProfileStore
  @EnvironmentObject private var radioSession: RadioSessionViewModel
  @EnvironmentObject private var recordingStore: RecordingStore
  @EnvironmentObject private var historyStore: ListeningHistoryStore

  var body: some View {
    TabView(selection: $navigationState.selectedTab) {
      ReceiverView()
        .tag(AppTab.receiver)
        .tabItem {
          Label("Receiver", systemImage: "dial.high")
        }

      RadiosView()
        .tag(AppTab.radios)
        .tabItem {
          Label("Radios", systemImage: "dot.radiowaves.left.and.right")
        }

      SettingsView()
        .tag(AppTab.settings)
        .tabItem {
          Label("Settings", systemImage: "gearshape")
        }
    }
    .tint(AppTheme.tint)
    .toolbarBackground(.regularMaterial, for: .tabBar)
    .toolbarBackground(.visible, for: .tabBar)
    .background(globalVoiceOverRotorBridge())
    .onAppear {
      SystemRemoteCommandController.shared.bind(radioSession: radioSession)
      processPendingShortcuts()
    }
    .onChange(of: scenePhase) { phase in
      if phase == .active {
        processPendingShortcuts()
      }
    }
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
        radioSession.tune(byStepCount: frequencyAdjustmentStepCount(forIncrement: true))
        announceFrequency(for: backend)
      },
      onTuneDecrement: {
        guard let backend else { return }
        radioSession.tune(byStepCount: frequencyAdjustmentStepCount(forIncrement: false))
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

  private func frequencyAdjustmentStepCount(forIncrement isIncrement: Bool) -> Int {
    let baseStep = radioSession.settings.tuningGestureDirection.frequencyAdjustmentStepCount
    return isIncrement ? baseStep : -baseStep
  }

  private func cycleTuneStep(by offset: Int, backend: SDRBackend) {
    let steps = radioSession.tuneStepOptions(for: backend)
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

  private func processPendingShortcuts() {
    AppShortcutCommandCenter.shared.processPendingCommands(
      navigationState: navigationState,
      profileStore: profileStore,
      radioSession: radioSession,
      recordingStore: recordingStore,
      historyStore: historyStore
    )
  }
}
