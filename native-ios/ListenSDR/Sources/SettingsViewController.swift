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
  var frequencyEntryCommitMode: FrequencyEntryCommitMode
  var tuneConfirmationWarningsEnabled: Bool
  var voiceOverRDSAnnouncementMode: VoiceOverRDSAnnouncementMode
  var magicTapAction: MagicTapAction
  var accessibilityInteractionSoundsEnabled: Bool
  var accessibilityInteractionSoundsVolume: Double
  var accessibilityInteractionSoundsMutedDuringRecording: Bool
  var accessibilitySelectionAnnouncementMode: ScreenReaderSelectionAnnouncementMode
  var accessibilitySelectionAnnouncementsEnabled: Bool
  var accessibilityConnectionSoundsEnabled: Bool
  var accessibilityRecordingSoundsEnabled: Bool
  var accessibilitySpeechLoudnessLevelingMode: SpeechLoudnessLevelingMode
  var accessibilitySpeechLoudnessCustomTargetRMS: Double
  var accessibilitySpeechLoudnessCustomMaximumGain: Double
  var accessibilitySpeechLoudnessCustomPeakLimit: Double
  var showTutorialOnLaunchEnabled: Bool
  var rememberSquelchOnConnectEnabled: Bool
  var openReceiverAfterHistoryRestore: Bool
  var showRecentFrequencies: Bool
  var includeRecentFrequenciesFromOtherReceivers: Bool
  var radiosSearchFiltersVisibility: RadiosSearchFiltersVisibility
  var keepStationPresetsExpanded: Bool
  var autoConnectSelectedProfileOnLaunch: Bool
  var autoConnectSelectedProfileAfterSelection: Bool
  var connectionNetworkPolicy: ConnectionNetworkPolicy
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
  var backupIncludesAppSettings: Bool
  var backupIncludesProfiles: Bool
  var backupIncludesProfilePasswords: Bool
  var backupIncludesFavorites: Bool
  var backupIncludesHistory: Bool

  static let empty = SettingsViewState(
    hasSavedSettingsSnapshot: false,
    dxNightModeEnabled: false,
    adaptiveScannerEnabled: false,
    tuningGestureDirection: .natural,
    tuneStepHz: RadioSessionSettings.default.tuneStepHz,
    tuneStepOptions: [],
    tuneStepPreferenceMode: .automatic,
    frequencyEntryCommitMode: .automatic,
    tuneConfirmationWarningsEnabled: false,
    voiceOverRDSAnnouncementMode: .off,
    magicTapAction: .toggleMute,
    accessibilityInteractionSoundsEnabled: RadioSessionSettings.default.accessibilityInteractionSoundsEnabled,
    accessibilityInteractionSoundsVolume: RadioSessionSettings.default.accessibilityInteractionSoundsVolume,
    accessibilityInteractionSoundsMutedDuringRecording: RadioSessionSettings.default.accessibilityInteractionSoundsMutedDuringRecording,
    accessibilitySelectionAnnouncementMode: RadioSessionSettings.default.accessibilitySelectionAnnouncementMode,
    accessibilitySelectionAnnouncementsEnabled: RadioSessionSettings.default.accessibilitySelectionAnnouncementsEnabled,
    accessibilityConnectionSoundsEnabled: RadioSessionSettings.default.accessibilityConnectionSoundsEnabled,
    accessibilityRecordingSoundsEnabled: RadioSessionSettings.default.accessibilityRecordingSoundsEnabled,
    accessibilitySpeechLoudnessLevelingMode: RadioSessionSettings.default.accessibilitySpeechLoudnessLevelingMode,
    accessibilitySpeechLoudnessCustomTargetRMS: RadioSessionSettings.default.accessibilitySpeechLoudnessCustomTargetRMS,
    accessibilitySpeechLoudnessCustomMaximumGain: RadioSessionSettings.default.accessibilitySpeechLoudnessCustomMaximumGain,
    accessibilitySpeechLoudnessCustomPeakLimit: RadioSessionSettings.default.accessibilitySpeechLoudnessCustomPeakLimit,
    showTutorialOnLaunchEnabled: RadioSessionSettings.default.showTutorialOnLaunchEnabled,
    rememberSquelchOnConnectEnabled: RadioSessionSettings.default.rememberSquelchOnConnectEnabled,
    openReceiverAfterHistoryRestore: false,
    showRecentFrequencies: RadioSessionSettings.default.showRecentFrequencies,
    includeRecentFrequenciesFromOtherReceivers: RadioSessionSettings.default.includeRecentFrequenciesFromOtherReceivers,
    radiosSearchFiltersVisibility: RadioSessionSettings.default.radiosSearchFiltersVisibility,
    keepStationPresetsExpanded: RadioSessionSettings.default.keepStationPresetsExpanded,
    autoConnectSelectedProfileOnLaunch: false,
    autoConnectSelectedProfileAfterSelection: false,
    connectionNetworkPolicy: RadioSessionSettings.default.connectionNetworkPolicy,
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
    canReconnectSelectedProfile: false,
    backupIncludesAppSettings: true,
    backupIncludesProfiles: true,
    backupIncludesProfilePasswords: false,
    backupIncludesFavorites: true,
    backupIncludesHistory: false
  )
}

@MainActor
final class SettingsViewController: ObservableObject {
  @Published private(set) var state: SettingsViewState = .empty
  @Published private(set) var isBound = false

  private weak var accessibilityState: AppAccessibilityState?
  private weak var radioSession: RadioSessionViewModel?
  private weak var profileStore: ProfileStore?
  private weak var favoritesStore: FavoritesStore?
  private weak var historyStore: ListeningHistoryStore?
  private let defaults = UserDefaults.standard
  private var cancellables: Set<AnyCancellable> = []
  private let backupIncludesAppSettingsKey = "ListenSDR.settingsBackup.includeAppSettings.v1"
  private let backupIncludesProfilesKey = "ListenSDR.settingsBackup.includeProfiles.v1"
  private let backupIncludesProfilePasswordsKey = "ListenSDR.settingsBackup.includeProfilePasswords.v1"
  private let backupIncludesFavoritesKey = "ListenSDR.settingsBackup.includeFavorites.v1"
  private let backupIncludesHistoryKey = "ListenSDR.settingsBackup.includeHistory.v1"

  func bind(
    radioSession: RadioSessionViewModel,
    profileStore: ProfileStore,
    favoritesStore: FavoritesStore,
    historyStore: ListeningHistoryStore,
    accessibilityState: AppAccessibilityState
  ) {
    let isSameBinding = self.radioSession === radioSession
      && self.profileStore === profileStore
      && self.favoritesStore === favoritesStore
      && self.historyStore === historyStore
      && self.accessibilityState === accessibilityState
    guard !isSameBinding else {
      refreshState(force: true)
      isBound = true
      return
    }

    self.radioSession = radioSession
    self.profileStore = profileStore
    self.favoritesStore = favoritesStore
    self.historyStore = historyStore
    self.accessibilityState = accessibilityState
    cancellables.removeAll()
    refreshState(force: true)
    isBound = true

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

    favoritesStore.objectWillChange
      .sink { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.refreshState()
        }
      }
      .store(in: &cancellables)

    historyStore.objectWillChange
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

  var settingsBackupSuggestedFilename: String {
    SettingsBackupDocument.defaultFilename
  }

  func makeSettingsBackupDocument() throws -> SettingsBackupDocument {
    guard let radioSession, let profileStore else {
      throw NSError(
        domain: "ListenSDR.SettingsBackup",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Settings are not available yet."]
      )
    }

    let options = currentBackupOptions()
    guard options.hasAnyEnabled else {
      throw NSError(
        domain: "ListenSDR.SettingsBackup",
        code: 7,
        userInfo: [NSLocalizedDescriptionKey: "Choose at least one type of data to include in the backup."]
      )
    }

    let payload = SettingsBackupPayload(
      settings: options.includeAppSettings ? radioSession.settings : nil,
      profiles: options.includeProfiles ? profileStore.exportProfilesForBackup(includePasswords: options.includeProfilePasswords) : nil,
      selectedProfileID: options.includeProfiles ? profileStore.selectedProfileID : nil,
      favoriteReceivers: options.includeFavorites ? favoritesStore?.favoriteReceivers : nil,
      favoriteStations: options.includeFavorites ? favoritesStore?.favoriteStations : nil,
      recentReceivers: options.includeHistory ? historyStore?.recentReceivers : nil,
      recentListening: options.includeHistory ? historyStore?.recentListening : nil,
      recentFrequencies: options.includeHistory ? historyStore?.recentFrequencies : nil
    )
    return try SettingsBackupDocument(data: RadioSessionSettingsBackupCodec.encode(payload: payload))
  }

  func importSettingsBackup(from data: Data) throws {
    guard let radioSession else {
      throw NSError(
        domain: "ListenSDR.SettingsBackup",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Settings are not available yet."]
      )
    }
    let imported = try RadioSessionSettingsBackupCodec.decodePayload(data)
    if let settings = imported.settings {
      radioSession.importSettingsBackup(settings)
    }
    if let profiles = imported.profiles {
      profileStore?.restoreProfilesFromBackup(profiles, selectedProfileID: imported.selectedProfileID)
    }
    if imported.favoriteReceivers != nil || imported.favoriteStations != nil {
      favoritesStore?.restoreBackup(
        favoriteReceivers: imported.favoriteReceivers ?? [],
        favoriteStations: imported.favoriteStations ?? []
      )
    }
    if imported.recentReceivers != nil || imported.recentListening != nil || imported.recentFrequencies != nil {
      historyStore?.restoreBackup(
        recentReceivers: imported.recentReceivers ?? [],
        recentListening: imported.recentListening ?? [],
        recentFrequencies: imported.recentFrequencies ?? []
      )
    }
    refreshState(force: true)
  }

  func restoreSavedSettingsSnapshot() {
    radioSession?.restoreSavedSettingsSnapshot()
    refreshState(force: true)
  }

  func setBackupIncludesAppSettings(_ value: Bool) {
    defaults.set(value, forKey: backupIncludesAppSettingsKey)
    refreshState(force: true)
  }

  func setBackupIncludesProfiles(_ value: Bool) {
    defaults.set(value, forKey: backupIncludesProfilesKey)
    if !value {
      defaults.set(false, forKey: backupIncludesProfilePasswordsKey)
    }
    refreshState(force: true)
  }

  func setBackupIncludesProfilePasswords(_ value: Bool) {
    defaults.set(value, forKey: backupIncludesProfilePasswordsKey)
    refreshState(force: true)
  }

  func setBackupIncludesFavorites(_ value: Bool) {
    defaults.set(value, forKey: backupIncludesFavoritesKey)
    refreshState(force: true)
  }

  func setBackupIncludesHistory(_ value: Bool) {
    defaults.set(value, forKey: backupIncludesHistoryKey)
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

  func setFrequencyEntryCommitMode(_ mode: FrequencyEntryCommitMode) {
    radioSession?.setFrequencyEntryCommitMode(mode)
    refreshState(force: true)
  }

  func setTuneConfirmationWarningsEnabled(_ isEnabled: Bool) {
    radioSession?.setTuneConfirmationWarningsEnabled(isEnabled)
    refreshState(force: true)
  }

  func setVoiceOverRDSAnnouncementMode(_ mode: VoiceOverRDSAnnouncementMode) {
    radioSession?.setVoiceOverRDSAnnouncementMode(mode)
    refreshState(force: true)
  }

  func setMagicTapAction(_ action: MagicTapAction) {
    radioSession?.setMagicTapAction(action)
    refreshState(force: true)
  }

  func setAccessibilityInteractionSoundsEnabled(_ isEnabled: Bool) {
    radioSession?.setAccessibilityInteractionSoundsEnabled(isEnabled)
    refreshState(force: true)
  }

  func setAccessibilityInteractionSoundsVolume(_ value: Double) {
    radioSession?.setAccessibilityInteractionSoundsVolume(value)
    refreshState(force: true)
  }

  func setAccessibilityInteractionSoundsMutedDuringRecording(_ isEnabled: Bool) {
    radioSession?.setAccessibilityInteractionSoundsMutedDuringRecording(isEnabled)
    refreshState(force: true)
  }

  func setAccessibilitySelectionAnnouncementsEnabled(_ isEnabled: Bool) {
    radioSession?.setAccessibilitySelectionAnnouncementsEnabled(isEnabled)
    refreshState(force: true)
  }

  func setAccessibilitySelectionAnnouncementMode(_ mode: ScreenReaderSelectionAnnouncementMode) {
    radioSession?.setAccessibilitySelectionAnnouncementMode(mode)
    refreshState(force: true)
  }

  func setAccessibilityConnectionSoundsEnabled(_ isEnabled: Bool) {
    radioSession?.setAccessibilityConnectionSoundsEnabled(isEnabled)
    refreshState(force: true)
  }

  func setAccessibilityRecordingSoundsEnabled(_ isEnabled: Bool) {
    radioSession?.setAccessibilityRecordingSoundsEnabled(isEnabled)
    refreshState(force: true)
  }

  func setSpeechLoudnessLevelingMode(_ mode: SpeechLoudnessLevelingMode) {
    radioSession?.setSpeechLoudnessLevelingMode(mode)
    refreshState(force: true)
  }

  func setSpeechLoudnessCustomTargetRMS(_ value: Double) {
    radioSession?.setSpeechLoudnessCustomTargetRMS(value)
    refreshState(force: true)
  }

  func setSpeechLoudnessCustomMaximumGain(_ value: Double) {
    radioSession?.setSpeechLoudnessCustomMaximumGain(value)
    refreshState(force: true)
  }

  func setSpeechLoudnessCustomPeakLimit(_ value: Double) {
    radioSession?.setSpeechLoudnessCustomPeakLimit(value)
    refreshState(force: true)
  }

  func setShowTutorialOnLaunchEnabled(_ isEnabled: Bool) {
    radioSession?.setShowTutorialOnLaunchEnabled(isEnabled)
    refreshState(force: true)
  }

  func consumeStartupTutorialAutoPresentationIfNeeded() -> Bool {
    let shouldPresent = radioSession?.consumeStartupTutorialAutoPresentationIfNeeded() ?? false
    refreshState(force: true)
    return shouldPresent
  }

  func setRememberSquelchOnConnectEnabled(_ isEnabled: Bool) {
    radioSession?.setRememberSquelchOnConnectEnabled(isEnabled)
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

  func setRadiosSearchFiltersVisibility(_ visibility: RadiosSearchFiltersVisibility) {
    radioSession?.setRadiosSearchFiltersVisibility(visibility)
    refreshState(force: true)
  }

  func setKeepStationPresetsExpanded(_ isEnabled: Bool) {
    radioSession?.setKeepStationPresetsExpanded(isEnabled)
    refreshState(force: true)
  }

  func setAutoConnectSelectedProfileOnLaunch(_ isEnabled: Bool) {
    radioSession?.setAutoConnectSelectedProfileOnLaunch(isEnabled)
    refreshState(force: true)
  }

  func setAutoConnectSelectedProfileAfterSelection(_ isEnabled: Bool) {
    radioSession?.setAutoConnectSelectedProfileAfterSelection(isEnabled)
    refreshState(force: true)
  }

  func setConnectionNetworkPolicy(_ policy: ConnectionNetworkPolicy) {
    radioSession?.setConnectionNetworkPolicy(policy)
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
    let backupOptions = currentBackupOptions()

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
      frequencyEntryCommitMode: radioSession.settings.frequencyEntryCommitMode,
      tuneConfirmationWarningsEnabled: radioSession.settings.tuneConfirmationWarningsEnabled,
      voiceOverRDSAnnouncementMode: radioSession.settings.voiceOverRDSAnnouncementMode,
      magicTapAction: radioSession.settings.magicTapAction,
      accessibilityInteractionSoundsEnabled: radioSession.settings.accessibilityInteractionSoundsEnabled,
      accessibilityInteractionSoundsVolume: radioSession.settings.accessibilityInteractionSoundsVolume,
      accessibilityInteractionSoundsMutedDuringRecording: radioSession.settings.accessibilityInteractionSoundsMutedDuringRecording,
      accessibilitySelectionAnnouncementMode: radioSession.settings.accessibilitySelectionAnnouncementMode,
      accessibilitySelectionAnnouncementsEnabled: radioSession.settings.accessibilitySelectionAnnouncementsEnabled,
      accessibilityConnectionSoundsEnabled: radioSession.settings.accessibilityConnectionSoundsEnabled,
      accessibilityRecordingSoundsEnabled: radioSession.settings.accessibilityRecordingSoundsEnabled,
      accessibilitySpeechLoudnessLevelingMode: radioSession.settings.accessibilitySpeechLoudnessLevelingMode,
      accessibilitySpeechLoudnessCustomTargetRMS: radioSession.settings.accessibilitySpeechLoudnessCustomTargetRMS,
      accessibilitySpeechLoudnessCustomMaximumGain: radioSession.settings.accessibilitySpeechLoudnessCustomMaximumGain,
      accessibilitySpeechLoudnessCustomPeakLimit: radioSession.settings.accessibilitySpeechLoudnessCustomPeakLimit,
      showTutorialOnLaunchEnabled: radioSession.settings.showTutorialOnLaunchEnabled,
      rememberSquelchOnConnectEnabled: radioSession.settings.rememberSquelchOnConnectEnabled,
      openReceiverAfterHistoryRestore: radioSession.settings.openReceiverAfterHistoryRestore,
      showRecentFrequencies: radioSession.settings.showRecentFrequencies,
      includeRecentFrequenciesFromOtherReceivers: radioSession.settings.includeRecentFrequenciesFromOtherReceivers,
      radiosSearchFiltersVisibility: radioSession.settings.radiosSearchFiltersVisibility,
      keepStationPresetsExpanded: radioSession.settings.keepStationPresetsExpanded,
      autoConnectSelectedProfileOnLaunch: radioSession.settings.autoConnectSelectedProfileOnLaunch,
      autoConnectSelectedProfileAfterSelection: radioSession.settings.autoConnectSelectedProfileAfterSelection,
      connectionNetworkPolicy: radioSession.settings.connectionNetworkPolicy,
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
      canReconnectSelectedProfile: profileStore?.selectedProfile != nil,
      backupIncludesAppSettings: backupOptions.includeAppSettings,
      backupIncludesProfiles: backupOptions.includeProfiles,
      backupIncludesProfilePasswords: backupOptions.includeProfilePasswords,
      backupIncludesFavorites: backupOptions.includeFavorites,
      backupIncludesHistory: backupOptions.includeHistory
    )
  }
}

private extension SettingsViewController {
  struct BackupOptions {
    let includeAppSettings: Bool
    let includeProfiles: Bool
    let includeProfilePasswords: Bool
    let includeFavorites: Bool
    let includeHistory: Bool

    var hasAnyEnabled: Bool {
      includeAppSettings || includeProfiles || includeFavorites || includeHistory
    }
  }

  func currentBackupOptions() -> BackupOptions {
    let includeProfiles = defaults.object(forKey: backupIncludesProfilesKey) as? Bool ?? true
    return BackupOptions(
      includeAppSettings: defaults.object(forKey: backupIncludesAppSettingsKey) as? Bool ?? true,
      includeProfiles: includeProfiles,
      includeProfilePasswords: includeProfiles && (defaults.object(forKey: backupIncludesProfilePasswordsKey) as? Bool ?? false),
      includeFavorites: defaults.object(forKey: backupIncludesFavoritesKey) as? Bool ?? true,
      includeHistory: defaults.object(forKey: backupIncludesHistoryKey) as? Bool ?? false
    )
  }
}
