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
  var tuneStepPreferenceMode: TuneStepPreferenceMode
  var fmdxTuneConfirmationWarningsEnabled: Bool
  var voiceOverRDSAnnouncementMode: VoiceOverRDSAnnouncementMode
  var openReceiverAfterHistoryRestore: Bool
  var showRecentFrequencies: Bool
  var includeRecentFrequenciesFromOtherReceivers: Bool
  var autoConnectSelectedProfileOnLaunch: Bool
  var saveChannelScannerResultsEnabled: Bool
  var stopChannelScannerOnSignal: Bool
  var filterChannelScannerInterferenceEnabled: Bool
  var channelScannerInterferenceFilterProfile: ChannelScannerInterferenceFilterProfile
  var saveFMDXScannerResultsEnabled: Bool
  var fmdxBandScanStartBehavior: FMDXBandScanStartBehavior
  var fmdxBandScanHitBehavior: FMDXBandScanHitBehavior
  var scannerDwellSeconds: Double
  var scannerHoldSeconds: Double
  var playDetectedChannelScannerSignalsEnabled: Bool
  var fmdxCustomScanSettleSeconds: Double
  var fmdxCustomScanMetadataWindowSeconds: Double
  var audioSuggestionScope: AudioSuggestionScope
  var currentFMDXAudioPreset: FMDXAudioTuningPreset
  var fmdxAudioStartupBufferSeconds: Double
  var fmdxAudioMaxLatencySeconds: Double
  var fmdxAudioPacketHoldSeconds: Double
  var mixWithOtherAudioApps: Bool
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
    tuneStepPreferenceMode: .manual,
    fmdxTuneConfirmationWarningsEnabled: false,
    voiceOverRDSAnnouncementMode: .off,
    openReceiverAfterHistoryRestore: false,
    showRecentFrequencies: RadioSessionSettings.default.showRecentFrequencies,
    includeRecentFrequenciesFromOtherReceivers: RadioSessionSettings.default.includeRecentFrequenciesFromOtherReceivers,
    autoConnectSelectedProfileOnLaunch: false,
    saveChannelScannerResultsEnabled: RadioSessionSettings.default.saveChannelScannerResultsEnabled,
    stopChannelScannerOnSignal: RadioSessionSettings.default.stopChannelScannerOnSignal,
    filterChannelScannerInterferenceEnabled: RadioSessionSettings.default.filterChannelScannerInterferenceEnabled,
    channelScannerInterferenceFilterProfile: RadioSessionSettings.default.channelScannerInterferenceFilterProfile,
    saveFMDXScannerResultsEnabled: false,
    fmdxBandScanStartBehavior: .fromBeginning,
    fmdxBandScanHitBehavior: .continuous,
    scannerDwellSeconds: RadioSessionSettings.default.scannerDwellSeconds,
    scannerHoldSeconds: RadioSessionSettings.default.scannerHoldSeconds,
    playDetectedChannelScannerSignalsEnabled: RadioSessionSettings.default.playDetectedChannelScannerSignalsEnabled,
    fmdxCustomScanSettleSeconds: RadioSessionSettings.default.fmdxCustomScanSettleSeconds,
    fmdxCustomScanMetadataWindowSeconds: RadioSessionSettings.default.fmdxCustomScanMetadataWindowSeconds,
    audioSuggestionScope: .fmDxOnly,
    currentFMDXAudioPreset: .balanced,
    fmdxAudioStartupBufferSeconds: RadioSessionSettings.default.fmdxAudioStartupBufferSeconds,
    fmdxAudioMaxLatencySeconds: RadioSessionSettings.default.fmdxAudioMaxLatencySeconds,
    fmdxAudioPacketHoldSeconds: RadioSessionSettings.default.fmdxAudioPacketHoldSeconds,
    mixWithOtherAudioApps: RadioSessionSettings.default.mixWithOtherAudioApps,
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

  func setTuneStepPreferenceMode(_ mode: TuneStepPreferenceMode) {
    radioSession?.setTuneStepPreferenceMode(mode)
    refreshState(force: true)
  }

  func setFMDXTuneConfirmationWarningsEnabled(_ isEnabled: Bool) {
    radioSession?.setFMDXTuneConfirmationWarningsEnabled(isEnabled)
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

  func setShowRecentFrequencies(_ isEnabled: Bool) {
    radioSession?.setShowRecentFrequencies(isEnabled)
    refreshState(force: true)
  }

  func setIncludeRecentFrequenciesFromOtherReceivers(_ isEnabled: Bool) {
    radioSession?.setIncludeRecentFrequenciesFromOtherReceivers(isEnabled)
    refreshState(force: true)
  }

  func setAutoConnectSelectedProfileOnLaunch(_ isEnabled: Bool) {
    radioSession?.setAutoConnectSelectedProfileOnLaunch(isEnabled)
    refreshState(force: true)
  }

  func setSaveChannelScannerResultsEnabled(_ isEnabled: Bool) {
    radioSession?.setSaveChannelScannerResultsEnabled(isEnabled)
    refreshState(force: true)
  }

  func setStopChannelScannerOnSignal(_ isEnabled: Bool) {
    radioSession?.setStopChannelScannerOnSignal(isEnabled)
    refreshState(force: true)
  }

  func setFilterChannelScannerInterferenceEnabled(_ isEnabled: Bool) {
    radioSession?.setFilterChannelScannerInterferenceEnabled(isEnabled)
    refreshState(force: true)
  }

  func setChannelScannerInterferenceFilterProfile(
    _ profile: ChannelScannerInterferenceFilterProfile
  ) {
    radioSession?.setChannelScannerInterferenceFilterProfile(profile)
    refreshState(force: true)
  }

  func setSaveFMDXScannerResultsEnabled(_ isEnabled: Bool) {
    radioSession?.setSaveFMDXScannerResultsEnabled(isEnabled)
    refreshState(force: true)
  }

  func setFMDXBandScanStartBehavior(_ behavior: FMDXBandScanStartBehavior) {
    radioSession?.setFMDXBandScanStartBehavior(behavior)
    refreshState(force: true)
  }

  func setFMDXBandScanHitBehavior(_ behavior: FMDXBandScanHitBehavior) {
    radioSession?.setFMDXBandScanHitBehavior(behavior)
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

  func setPlayDetectedChannelScannerSignalsEnabled(_ isEnabled: Bool) {
    radioSession?.setPlayDetectedChannelScannerSignalsEnabled(isEnabled)
    refreshState(force: true)
  }

  func setFMDXCustomScanSettleSeconds(_ value: Double) {
    radioSession?.setFMDXCustomScanSettleSeconds(value)
    refreshState(force: true)
  }

  func setFMDXCustomScanMetadataWindowSeconds(_ value: Double) {
    radioSession?.setFMDXCustomScanMetadataWindowSeconds(value)
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

  func setMixWithOtherAudioApps(_ isEnabled: Bool) {
    radioSession?.setMixWithOtherAudioApps(isEnabled)
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
    let effectiveTuneStep = radioSession.effectiveTuneStepHz(for: backend)
    let currentTuneStep = tuneStepOptions.contains(effectiveTuneStep)
      ? effectiveTuneStep
      : (tuneStepOptions.first ?? effectiveTuneStep)
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
      tuneStepPreferenceMode: radioSession.settings.tuneStepPreferenceMode,
      fmdxTuneConfirmationWarningsEnabled: radioSession.settings.fmdxTuneConfirmationWarningsEnabled,
      voiceOverRDSAnnouncementMode: radioSession.settings.voiceOverRDSAnnouncementMode,
      openReceiverAfterHistoryRestore: radioSession.settings.openReceiverAfterHistoryRestore,
      showRecentFrequencies: radioSession.settings.showRecentFrequencies,
      includeRecentFrequenciesFromOtherReceivers: radioSession.settings.includeRecentFrequenciesFromOtherReceivers,
      autoConnectSelectedProfileOnLaunch: radioSession.settings.autoConnectSelectedProfileOnLaunch,
      saveChannelScannerResultsEnabled: radioSession.settings.saveChannelScannerResultsEnabled,
      stopChannelScannerOnSignal: radioSession.settings.stopChannelScannerOnSignal,
      filterChannelScannerInterferenceEnabled: radioSession.settings.filterChannelScannerInterferenceEnabled,
      channelScannerInterferenceFilterProfile: radioSession.settings.channelScannerInterferenceFilterProfile,
      saveFMDXScannerResultsEnabled: radioSession.settings.saveFMDXScannerResultsEnabled,
      fmdxBandScanStartBehavior: radioSession.settings.fmdxBandScanStartBehavior,
      fmdxBandScanHitBehavior: radioSession.settings.fmdxBandScanHitBehavior,
      scannerDwellSeconds: radioSession.settings.scannerDwellSeconds,
      scannerHoldSeconds: radioSession.settings.scannerHoldSeconds,
      playDetectedChannelScannerSignalsEnabled: radioSession.settings.playDetectedChannelScannerSignalsEnabled,
      fmdxCustomScanSettleSeconds: radioSession.settings.fmdxCustomScanSettleSeconds,
      fmdxCustomScanMetadataWindowSeconds: radioSession.settings.fmdxCustomScanMetadataWindowSeconds,
      audioSuggestionScope: radioSession.settings.audioSuggestionScope,
      currentFMDXAudioPreset: radioSession.currentFMDXAudioPreset,
      fmdxAudioStartupBufferSeconds: radioSession.settings.fmdxAudioStartupBufferSeconds,
      fmdxAudioMaxLatencySeconds: radioSession.settings.fmdxAudioMaxLatencySeconds,
      fmdxAudioPacketHoldSeconds: radioSession.settings.fmdxAudioPacketHoldSeconds,
      mixWithOtherAudioApps: radioSession.settings.mixWithOtherAudioApps,
      audioQualityInsight: audioQualityInsight,
      audioSuggestionInsight: audioSuggestionInsight,
      canReconnectSelectedProfile: profileStore?.selectedProfile != nil
    )
  }
}
