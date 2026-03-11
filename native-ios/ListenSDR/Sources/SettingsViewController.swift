import Foundation
import Combine
import UIKit

struct SettingsViewState: Equatable {
  struct AudioQualityInsight: Equatable {
    let score: Int
    let level: FMDXAudioQualityLevel
  }

  struct AudioSuggestionInsight: Equatable {
    let preset: FMDXAudioTuningPreset
    let localizedReason: String
  }

  var hasSavedSettingsSnapshot: Bool
  var dxNightModeEnabled: Bool
  var adaptiveScannerEnabled: Bool
  var tuningGestureDirection: TuningGestureDirection
  var tuneStepHz: Int
  var tuneStepOptions: [Int]
  var voiceOverRDSAnnouncementMode: VoiceOverRDSAnnouncementMode
  var openReceiverAfterHistoryRestore: Bool
  var scannerDwellSeconds: Double
  var scannerHoldSeconds: Double
  var audioSuggestionScope: AudioSuggestionScope
  var currentFMDXAudioPreset: FMDXAudioTuningPreset
  var fmdxAudioStartupBufferSeconds: Double
  var fmdxAudioMaxLatencySeconds: Double
  var fmdxAudioPacketHoldSeconds: Double
  var audioQualityInsight: AudioQualityInsight?
  var audioSuggestionInsight: AudioSuggestionInsight?
  var canReconnectSelectedProfile: Bool

  static let empty = SettingsViewState(
    hasSavedSettingsSnapshot: false,
    dxNightModeEnabled: false,
    adaptiveScannerEnabled: false,
    tuningGestureDirection: .natural,
    tuneStepHz: RadioSessionSettings.default.tuneStepHz,
    tuneStepOptions: [],
    voiceOverRDSAnnouncementMode: .off,
    openReceiverAfterHistoryRestore: false,
    scannerDwellSeconds: RadioSessionSettings.default.scannerDwellSeconds,
    scannerHoldSeconds: RadioSessionSettings.default.scannerHoldSeconds,
    audioSuggestionScope: .fmDxOnly,
    currentFMDXAudioPreset: .balanced,
    fmdxAudioStartupBufferSeconds: RadioSessionSettings.default.fmdxAudioStartupBufferSeconds,
    fmdxAudioMaxLatencySeconds: RadioSessionSettings.default.fmdxAudioMaxLatencySeconds,
    fmdxAudioPacketHoldSeconds: RadioSessionSettings.default.fmdxAudioPacketHoldSeconds,
    audioQualityInsight: nil,
    audioSuggestionInsight: nil,
    canReconnectSelectedProfile: false
  )
}

@MainActor
final class SettingsViewController: ObservableObject {
  @Published private(set) var state: SettingsViewState = .empty

  private weak var accessibilityState: AppAccessibilityState?
  private weak var radioSession: RadioSessionViewModel?
  private weak var profileStore: ProfileStore?
  private var cancellables: Set<AnyCancellable> = []

  func bind(
    radioSession: RadioSessionViewModel,
    profileStore: ProfileStore,
    accessibilityState: AppAccessibilityState
  ) {
    let isSameBinding = self.radioSession === radioSession
      && self.profileStore === profileStore
      && self.accessibilityState === accessibilityState
    guard !isSameBinding else {
      refreshState(force: true)
      return
    }

    self.radioSession = radioSession
    self.profileStore = profileStore
    self.accessibilityState = accessibilityState
    cancellables.removeAll()
    refreshState(force: true)

    radioSession.objectWillChange
      .sink { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.refreshState()
        }
      }
      .store(in: &cancellables)

    profileStore.objectWillChange
      .sink { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.refreshState()
        }
      }
      .store(in: &cancellables)

    accessibilityState.objectWillChange
      .sink { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.refreshState()
        }
      }
      .store(in: &cancellables)
  }

  func saveCurrentSettingsSnapshot() {
    radioSession?.saveCurrentSettingsSnapshot()
    refreshState(force: true)
  }

  func restoreSavedSettingsSnapshot() {
    radioSession?.restoreSavedSettingsSnapshot()
    refreshState(force: true)
  }

  func setDXNightModeEnabled(_ isEnabled: Bool) {
    radioSession?.setDXNightModeEnabled(isEnabled)
    refreshState(force: true)
  }

  func setAdaptiveScannerEnabled(_ isEnabled: Bool) {
    radioSession?.setAdaptiveScannerEnabled(isEnabled)
    refreshState(force: true)
  }

  func setTuningGestureDirection(_ direction: TuningGestureDirection) {
    radioSession?.setTuningGestureDirection(direction)
    refreshState(force: true)
  }

  func setTuneStepHz(_ stepHz: Int) {
    radioSession?.setTuneStepHz(stepHz)
    refreshState(force: true)
  }

  func setVoiceOverRDSAnnouncementMode(_ mode: VoiceOverRDSAnnouncementMode) {
    radioSession?.setVoiceOverRDSAnnouncementMode(mode)
    refreshState(force: true)
  }

  func setOpenReceiverAfterHistoryRestore(_ isEnabled: Bool) {
    radioSession?.setOpenReceiverAfterHistoryRestore(isEnabled)
    refreshState(force: true)
  }

  func setScannerDwellSeconds(_ value: Double) {
    radioSession?.setScannerDwellSeconds(value)
    refreshState(force: true)
  }

  func setScannerHoldSeconds(_ value: Double) {
    radioSession?.setScannerHoldSeconds(value)
    refreshState(force: true)
  }

  func setAudioSuggestionScope(_ scope: AudioSuggestionScope) {
    radioSession?.setAudioSuggestionScope(scope)
    refreshState(force: true)
  }

  func applyFMDXAudioPreset(_ preset: FMDXAudioTuningPreset) {
    radioSession?.applyFMDXAudioPreset(preset)
    refreshState(force: true)
  }

  func setFMDXAudioStartupBufferSeconds(_ value: Double) {
    radioSession?.setFMDXAudioStartupBufferSeconds(value)
    refreshState(force: true)
  }

  func setFMDXAudioMaxLatencySeconds(_ value: Double) {
    radioSession?.setFMDXAudioMaxLatencySeconds(value)
    refreshState(force: true)
  }

  func setFMDXAudioPacketHoldSeconds(_ value: Double) {
    radioSession?.setFMDXAudioPacketHoldSeconds(value)
    refreshState(force: true)
  }

  func resetFMDXAudioTuning() {
    radioSession?.resetFMDXAudioTuning()
    refreshState(force: true)
  }

  func reconnectSelectedProfile() {
    guard
      let radioSession,
      let profile = profileStore?.selectedProfile
    else {
      return
    }

    radioSession.reconnect(to: profile)
    refreshState(force: true)
  }

  func resetDSPSettings() {
    radioSession?.resetDSPSettings()
    refreshState(force: true)
  }

  private func refreshState(force: Bool = false) {
    let nextState = makeState()
    guard force || nextState != state else { return }
    state = nextState
  }

  private func makeState() -> SettingsViewState {
    guard let radioSession else { return .empty }

    let backend = radioSession.currentTuningBackend ?? profileStore?.selectedProfile?.backend
    let tuneStepOptions = backend.map { radioSession.tuneStepOptions(for: $0) } ?? []
    let currentTuneStep = tuneStepOptions.contains(radioSession.settings.tuneStepHz)
      ? radioSession.settings.tuneStepHz
      : (tuneStepOptions.first ?? radioSession.settings.tuneStepHz)
    let shouldFreezeLiveAudioInsights = UIAccessibility.isVoiceOverRunning
      && accessibilityState?.selectedTab == .settings
    let audioQualityInsight: SettingsViewState.AudioQualityInsight? = shouldFreezeLiveAudioInsights
      ? state.audioQualityInsight
      : radioSession.fmdxAudioQualityReport.map {
        SettingsViewState.AudioQualityInsight(score: $0.score, level: $0.level)
      }
    let audioSuggestionInsight: SettingsViewState.AudioSuggestionInsight? = shouldFreezeLiveAudioInsights
      ? state.audioSuggestionInsight
      : radioSession.audioPresetSuggestion.map {
        SettingsViewState.AudioSuggestionInsight(
          preset: $0.preset,
          localizedReason: $0.localizedReason
        )
      }

    return SettingsViewState(
      hasSavedSettingsSnapshot: radioSession.hasSavedSettingsSnapshot,
      dxNightModeEnabled: radioSession.settings.dxNightModeEnabled,
      adaptiveScannerEnabled: radioSession.settings.adaptiveScannerEnabled,
      tuningGestureDirection: radioSession.settings.tuningGestureDirection,
      tuneStepHz: currentTuneStep,
      tuneStepOptions: tuneStepOptions,
      voiceOverRDSAnnouncementMode: radioSession.settings.voiceOverRDSAnnouncementMode,
      openReceiverAfterHistoryRestore: radioSession.settings.openReceiverAfterHistoryRestore,
      scannerDwellSeconds: radioSession.settings.scannerDwellSeconds,
      scannerHoldSeconds: radioSession.settings.scannerHoldSeconds,
      audioSuggestionScope: radioSession.settings.audioSuggestionScope,
      currentFMDXAudioPreset: radioSession.currentFMDXAudioPreset,
      fmdxAudioStartupBufferSeconds: radioSession.settings.fmdxAudioStartupBufferSeconds,
      fmdxAudioMaxLatencySeconds: radioSession.settings.fmdxAudioMaxLatencySeconds,
      fmdxAudioPacketHoldSeconds: radioSession.settings.fmdxAudioPacketHoldSeconds,
      audioQualityInsight: audioQualityInsight,
      audioSuggestionInsight: audioSuggestionInsight,
      canReconnectSelectedProfile: profileStore?.selectedProfile != nil
    )
  }
}
