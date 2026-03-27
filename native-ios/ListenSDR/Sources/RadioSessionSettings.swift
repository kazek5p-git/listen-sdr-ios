import Foundation
import ListenSDRCore

enum VoiceOverRDSAnnouncementMode: String, Codable, CaseIterable, Identifiable {
  case off
  case stationOnly
  case full

  var id: String { rawValue }

  var localizedTitle: String {
    switch self {
    case .off:
      return L10n.text("settings.accessibility.voiceover_rds_mode.off")
    case .stationOnly:
      return L10n.text("settings.accessibility.voiceover_rds_mode.station_only")
    case .full:
      return L10n.text("settings.accessibility.voiceover_rds_mode.full")
    }
  }
}

enum MagicTapAction: String, Codable, CaseIterable, Identifiable {
  case toggleMute
  case disconnect
  case toggleRecording

  var id: String { rawValue }

  private static let legacyStopRecordingIfActiveOtherwiseToggleMuteRawValue =
    "stopRecordingIfActiveOtherwiseToggleMute"

  var localizedTitle: String {
    switch self {
    case .toggleMute:
      return L10n.text("settings.accessibility.magic_tap.toggle_mute")
    case .disconnect:
      return L10n.text("settings.accessibility.magic_tap.disconnect")
    case .toggleRecording:
      return L10n.text("settings.accessibility.magic_tap.stop_recording_if_active_otherwise_toggle_mute")
    }
  }

  var localizedDetail: String {
    switch self {
    case .toggleMute:
      return L10n.text("settings.accessibility.magic_tap.toggle_mute.detail")
    case .disconnect:
      return L10n.text("settings.accessibility.magic_tap.disconnect.detail")
    case .toggleRecording:
      return L10n.text("settings.accessibility.magic_tap.stop_recording_if_active_otherwise_toggle_mute.detail")
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)

    switch rawValue {
    case Self.legacyStopRecordingIfActiveOtherwiseToggleMuteRawValue:
      self = .toggleRecording
    case let value where MagicTapAction(rawValue: value) != nil:
      self = MagicTapAction(rawValue: value)!
    default:
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Unknown MagicTapAction raw value: \(rawValue)"
      )
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum RadiosSearchFiltersVisibility: String, Codable, CaseIterable, Identifiable {
  case alwaysVisible
  case whileSearchFieldActive

  var id: String { rawValue }

  var localizedTitle: String {
    switch self {
    case .alwaysVisible:
      return L10n.text("settings.radios.search_filters.always_visible")
    case .whileSearchFieldActive:
      return L10n.text("settings.radios.search_filters.while_search_active")
    }
  }

  var localizedDetail: String {
    switch self {
    case .alwaysVisible:
      return L10n.text("settings.radios.search_filters.always_visible.detail")
    case .whileSearchFieldActive:
      return L10n.text("settings.radios.search_filters.while_search_active.detail")
    }
  }
}

enum AudioSuggestionScope: String, Codable, CaseIterable, Identifiable {
  case off
  case fmDxOnly
  case allSupportedBackends

  var id: String { rawValue }

  var localizedTitle: String {
    switch self {
    case .off:
      return L10n.text("settings.audio.suggestion_scope.off")
    case .fmDxOnly:
      return L10n.text("settings.audio.suggestion_scope.fmdx_only")
    case .allSupportedBackends:
      return L10n.text("settings.audio.suggestion_scope.all_supported")
    }
  }

  var localizedDetail: String {
    switch self {
    case .off:
      return L10n.text("settings.audio.suggestion_scope.off.detail")
    case .fmDxOnly:
      return L10n.text("settings.audio.suggestion_scope.fmdx_only.detail")
    case .allSupportedBackends:
      return L10n.text("settings.audio.suggestion_scope.all_supported.detail")
    }
  }
}

enum TuningGestureDirection: String, Codable, CaseIterable, Identifiable {
  case natural
  case reversed

  var id: String { rawValue }

  var localizedTitle: String {
    switch self {
    case .natural:
      return L10n.text("settings.tuning.direction.natural")
    case .reversed:
      return L10n.text("settings.tuning.direction.reversed")
    }
  }

  var localizedDetail: String {
    switch self {
    case .natural:
      return L10n.text("settings.tuning.direction.natural.detail")
    case .reversed:
      return L10n.text("settings.tuning.direction.reversed.detail")
    }
  }

  var frequencyAdjustmentStepCount: Int {
    switch self {
    case .natural:
      return 1
    case .reversed:
      return -1
    }
  }
}

extension FMDXBandScanStartBehavior {
  var localizedTitle: String {
    switch self {
    case .fromBeginning:
      return L10n.text("settings.scanner.fmdx_start_behavior.from_beginning")
    case .fromCurrentFrequency:
      return L10n.text("settings.scanner.fmdx_start_behavior.from_current_frequency")
    }
  }
}

enum FMDXBandScanHitBehavior: String, Codable, CaseIterable, Identifiable {
  case continuous
  case stopOnSignal

  var id: String { rawValue }

  var localizedTitle: String {
    switch self {
    case .continuous:
      return L10n.text("settings.scanner.fmdx_hit_behavior.continuous")
    case .stopOnSignal:
      return L10n.text("settings.scanner.fmdx_hit_behavior.stop_on_signal")
    }
  }
}

extension ChannelScannerInterferenceFilterProfile {
  var localizedTitle: String {
    switch self {
    case .gentle:
      return L10n.text("settings.scanner.interference_profile.gentle")
    case .standard:
      return L10n.text("settings.scanner.interference_profile.standard")
    case .strong:
      return L10n.text("settings.scanner.interference_profile.strong")
    }
  }

  var localizedDetail: String {
    switch self {
    case .gentle:
      return L10n.text("settings.scanner.interference_profile.gentle.detail")
    case .standard:
      return L10n.text("settings.scanner.interference_profile.standard.detail")
    case .strong:
      return L10n.text("settings.scanner.interference_profile.strong.detail")
    }
  }
}

enum FMDXAudioTuningPreset: String, CaseIterable, Identifiable {
  case lowLatency
  case balanced
  case stable
  case weakServer
  case custom

  var id: String { rawValue }

  static var selectableCases: [FMDXAudioTuningPreset] {
    [.lowLatency, .balanced, .stable, .weakServer]
  }

  var localizedTitle: String {
    switch self {
    case .lowLatency:
      return L10n.text("settings.audio.preset.low_latency")
    case .balanced:
      return L10n.text("settings.audio.preset.balanced")
    case .stable:
      return L10n.text("settings.audio.preset.stable")
    case .weakServer:
      return L10n.text("settings.audio.preset.weak_server")
    case .custom:
      return L10n.text("settings.audio.preset.custom")
    }
  }

  var localizedDetail: String {
    switch self {
    case .lowLatency:
      return L10n.text("settings.audio.preset.low_latency.detail")
    case .balanced:
      return L10n.text("settings.audio.preset.balanced.detail")
    case .stable:
      return L10n.text("settings.audio.preset.stable.detail")
    case .weakServer:
      return L10n.text("settings.audio.preset.weak_server.detail")
    case .custom:
      return L10n.text("settings.audio.preset.custom.detail")
    }
  }

  var tuningValues: (startupBufferSeconds: Double, maxLatencySeconds: Double, packetHoldSeconds: Double)? {
    switch self {
    case .lowLatency:
      return (0.35, 1.10, 0.08)
    case .balanced:
      return (
        RadioSessionSettings.default.fmdxAudioStartupBufferSeconds,
        RadioSessionSettings.default.fmdxAudioMaxLatencySeconds,
        RadioSessionSettings.default.fmdxAudioPacketHoldSeconds
      )
    case .stable:
      return (0.80, 2.20, 0.20)
    case .weakServer:
      return (1.10, 2.80, 0.28)
    case .custom:
      return nil
    }
  }

  static func matching(
    startupBufferSeconds: Double,
    maxLatencySeconds: Double,
    packetHoldSeconds: Double
  ) -> FMDXAudioTuningPreset {
    let tolerance = 0.0001
    for preset in selectableCases {
      guard let values = preset.tuningValues else { continue }
      let startupMatches = abs(values.startupBufferSeconds - startupBufferSeconds) < tolerance
      let latencyMatches = abs(values.maxLatencySeconds - maxLatencySeconds) < tolerance
      let holdMatches = abs(values.packetHoldSeconds - packetHoldSeconds) < tolerance
      if startupMatches && latencyMatches && holdMatches {
        return preset
      }
    }
    return .custom
  }
}

struct FMDXAudioPresetSuggestion {
  let preset: FMDXAudioTuningPreset
  let reasonKey: String

  var localizedReason: String {
    L10n.text(reasonKey)
  }
}

enum FMDXAudioQualityLevel: String {
  case excellent
  case good
  case fair
  case poor
  case critical

  var localizedTitle: String {
    switch self {
    case .excellent:
      return L10n.text("diagnostics.audio_quality.level.excellent")
    case .good:
      return L10n.text("diagnostics.audio_quality.level.good")
    case .fair:
      return L10n.text("diagnostics.audio_quality.level.fair")
    case .poor:
      return L10n.text("diagnostics.audio_quality.level.poor")
    case .critical:
      return L10n.text("diagnostics.audio_quality.level.critical")
    }
  }
}

struct FMDXAudioQualityReport {
  let score: Int
  let level: FMDXAudioQualityLevel
  let summaryKey: String
  let queuedDurationSeconds: Double
  let queuedBufferCount: Int
  let outputGapSeconds: Double
  let latencyTrimAgeSeconds: Double?
  let signalDBf: Double?

  var localizedSummary: String {
    L10n.text(summaryKey)
  }
}

struct FMDXAudioQualitySample: Identifiable {
  let id: UUID
  let date: Date
  let score: Int
  let level: FMDXAudioQualityLevel
}

struct RadioSessionSettings: Codable, Equatable {
  var frequencyHz: Int
  var tuneStepHz: Int
  var preferredTuneStepHz: Int
  var tuneStepPreferenceMode: TuneStepPreferenceMode
  var mode: DemodulationMode
  var rfGain: Double
  var audioVolume: Double
  var audioMuted: Bool
  var mixWithOtherAudioApps: Bool
  var agcEnabled: Bool
  var imsEnabled: Bool
  var noiseReductionEnabled: Bool
  var squelchEnabled: Bool
  var openWebRXSquelchLevel: Int
  var kiwiSquelchThreshold: Int
  var kiwiNoiseBlankerAlgorithm: KiwiNoiseBlankerAlgorithm
  var kiwiNoiseBlankerGate: Int
  var kiwiNoiseBlankerThreshold: Int
  var kiwiNoiseBlankerWildThreshold: Double
  var kiwiNoiseBlankerWildTaps: Int
  var kiwiNoiseBlankerWildImpulseSamples: Int
  var kiwiNoiseFilterAlgorithm: KiwiNoiseFilterAlgorithm
  var kiwiDenoiseEnabled: Bool
  var kiwiAutonotchEnabled: Bool
  var kiwiPassbandsByMode: [String: ReceiverBandpass]
  var kiwiWaterfallSpeed: Int
  var kiwiWaterfallWindowFunction: Int
  var kiwiWaterfallInterpolation: Int
  var kiwiWaterfallCICCompensation: Bool
  var kiwiWaterfallZoom: Int
  var kiwiWaterfallPanOffsetBins: Int
  var kiwiWaterfallMinDB: Int
  var kiwiWaterfallMaxDB: Int
  var showRdsErrorCounters: Bool
  var voiceOverRDSAnnouncementMode: VoiceOverRDSAnnouncementMode
  var magicTapAction: MagicTapAction
  var accessibilityInteractionSoundsEnabled: Bool
  var accessibilityInteractionSoundsVolume: Double
  var accessibilityInteractionSoundsMutedDuringRecording: Bool
  var accessibilitySelectionAnnouncementsEnabled: Bool
  var accessibilityConnectionSoundsEnabled: Bool
  var accessibilityRecordingSoundsEnabled: Bool
  var accessibilitySpeechLoudnessLevelingEnabled: Bool
  var showTutorialOnLaunchEnabled: Bool
  var rememberSquelchOnConnectEnabled: Bool
  var dxNightModeEnabled: Bool
  var autoFilterProfileEnabled: Bool
  var adaptiveScannerEnabled: Bool
  var scannerDwellSeconds: Double
  var scannerHoldSeconds: Double
  var playDetectedChannelScannerSignalsEnabled: Bool
  var fmdxAudioStartupBufferSeconds: Double
  var fmdxAudioMaxLatencySeconds: Double
  var fmdxAudioPacketHoldSeconds: Double
  var fmdxCustomScanSettleSeconds: Double
  var fmdxCustomScanMetadataWindowSeconds: Double
  var audioSuggestionScope: AudioSuggestionScope
  var tuningGestureDirection: TuningGestureDirection
  var fmdxTuneConfirmationWarningsEnabled: Bool
  var openReceiverAfterHistoryRestore: Bool
  var showRecentFrequencies: Bool
  var includeRecentFrequenciesFromOtherReceivers: Bool
  var radiosSearchFiltersVisibility: RadiosSearchFiltersVisibility
  var autoConnectSelectedProfileOnLaunch: Bool
  var saveChannelScannerResultsEnabled: Bool
  var stopChannelScannerOnSignal: Bool
  var filterChannelScannerInterferenceEnabled: Bool
  var channelScannerInterferenceFilterProfile: ChannelScannerInterferenceFilterProfile
  var saveFMDXScannerResultsEnabled: Bool
  var fmdxBandScanStartBehavior: FMDXBandScanStartBehavior
  var fmdxBandScanHitBehavior: FMDXBandScanHitBehavior

  var voiceOverAnnouncesRDSChanges: Bool {
    get { voiceOverRDSAnnouncementMode != .off }
    set { voiceOverRDSAnnouncementMode = newValue ? .full : .off }
  }

  static let supportedTuneStepsHz: [Int] = [
    10, 50, 100, 500, 1_000, 5_000, 6_250, 8_330, 9_000, 10_000, 12_500, 25_000,
    50_000, 100_000, 200_000
  ]

  static let `default` = RadioSessionSettings(
    frequencyHz: 7_050_000,
    tuneStepHz: 100,
    preferredTuneStepHz: 100,
    tuneStepPreferenceMode: .manual,
    mode: .am,
    rfGain: 30,
    audioVolume: 0.85,
    audioMuted: false,
    mixWithOtherAudioApps: false,
    agcEnabled: true,
    imsEnabled: true,
    noiseReductionEnabled: false,
    squelchEnabled: false,
    openWebRXSquelchLevel: -95,
    kiwiSquelchThreshold: 6,
    kiwiNoiseBlankerAlgorithm: .off,
    kiwiNoiseBlankerGate: 100,
    kiwiNoiseBlankerThreshold: 50,
    kiwiNoiseBlankerWildThreshold: 0.95,
    kiwiNoiseBlankerWildTaps: 10,
    kiwiNoiseBlankerWildImpulseSamples: 7,
    kiwiNoiseFilterAlgorithm: .off,
    kiwiDenoiseEnabled: false,
    kiwiAutonotchEnabled: false,
    kiwiPassbandsByMode: [:],
    kiwiWaterfallSpeed: KiwiWaterfallRate.slow.rawValue,
    kiwiWaterfallWindowFunction: KiwiWaterfallWindowFunction.blackmanHarris.rawValue,
    kiwiWaterfallInterpolation: KiwiWaterfallInterpolation.dropSamples.rawValue,
    kiwiWaterfallCICCompensation: true,
    kiwiWaterfallZoom: 0,
    kiwiWaterfallPanOffsetBins: 0,
    kiwiWaterfallMinDB: -145,
    kiwiWaterfallMaxDB: -20,
    showRdsErrorCounters: false,
    voiceOverRDSAnnouncementMode: .off,
    magicTapAction: .toggleMute,
    accessibilityInteractionSoundsEnabled: false,
    accessibilityInteractionSoundsVolume: 1.0,
    accessibilityInteractionSoundsMutedDuringRecording: false,
    accessibilitySelectionAnnouncementsEnabled: false,
    accessibilityConnectionSoundsEnabled: false,
    accessibilityRecordingSoundsEnabled: true,
    accessibilitySpeechLoudnessLevelingEnabled: false,
    showTutorialOnLaunchEnabled: true,
    rememberSquelchOnConnectEnabled: true,
    dxNightModeEnabled: false,
    autoFilterProfileEnabled: false,
    adaptiveScannerEnabled: false,
    scannerDwellSeconds: 1.5,
    scannerHoldSeconds: 4.0,
    playDetectedChannelScannerSignalsEnabled: true,
    fmdxAudioStartupBufferSeconds: 0.55,
    fmdxAudioMaxLatencySeconds: 1.8,
    fmdxAudioPacketHoldSeconds: 0.14,
    fmdxCustomScanSettleSeconds: 0.16,
    fmdxCustomScanMetadataWindowSeconds: 0.90,
    audioSuggestionScope: .fmDxOnly,
    tuningGestureDirection: .natural,
    fmdxTuneConfirmationWarningsEnabled: false,
    openReceiverAfterHistoryRestore: false,
    showRecentFrequencies: true,
    includeRecentFrequenciesFromOtherReceivers: false,
    radiosSearchFiltersVisibility: .alwaysVisible,
    autoConnectSelectedProfileOnLaunch: false,
    saveChannelScannerResultsEnabled: false,
    stopChannelScannerOnSignal: false,
    filterChannelScannerInterferenceEnabled: false,
    channelScannerInterferenceFilterProfile: .standard,
    saveFMDXScannerResultsEnabled: false,
    fmdxBandScanStartBehavior: .fromBeginning,
    fmdxBandScanHitBehavior: .continuous
  )

  private enum CodingKeys: String, CodingKey {
    case frequencyHz
    case tuneStepHz
    case preferredTuneStepHz
    case tuneStepPreferenceMode
    case mode
    case rfGain
    case audioVolume
    case audioMuted
    case mixWithOtherAudioApps
    case agcEnabled
    case imsEnabled
    case noiseReductionEnabled
    case squelchEnabled
    case openWebRXSquelchLevel
    case kiwiSquelchThreshold
    case kiwiNoiseBlankerAlgorithm
    case kiwiNoiseBlankerGate
    case kiwiNoiseBlankerThreshold
    case kiwiNoiseBlankerWildThreshold
    case kiwiNoiseBlankerWildTaps
    case kiwiNoiseBlankerWildImpulseSamples
    case kiwiNoiseFilterAlgorithm
    case kiwiDenoiseEnabled
    case kiwiAutonotchEnabled
    case kiwiPassbandsByMode
    case kiwiWaterfallSpeed
    case kiwiWaterfallWindowFunction
    case kiwiWaterfallInterpolation
    case kiwiWaterfallCICCompensation
    case kiwiWaterfallZoom
    case kiwiWaterfallPanOffsetBins
    case kiwiWaterfallMinDB
    case kiwiWaterfallMaxDB
    case showRdsErrorCounters
    case voiceOverRDSAnnouncementMode
    case voiceOverAnnouncesRDSChanges
    case magicTapAction
    case accessibilityInteractionSoundsEnabled
    case accessibilityInteractionSoundsVolume
    case accessibilityInteractionSoundsMutedDuringRecording
    case accessibilitySelectionAnnouncementsEnabled
    case accessibilityConnectionSoundsEnabled
    case accessibilityRecordingSoundsEnabled
    case accessibilitySpeechLoudnessLevelingEnabled
    case showTutorialOnLaunchEnabled
    case rememberSquelchOnConnectEnabled
    case dxNightModeEnabled
    case autoFilterProfileEnabled
    case adaptiveScannerEnabled
    case scannerDwellSeconds
    case scannerHoldSeconds
    case playDetectedChannelScannerSignalsEnabled
    case fmdxAudioStartupBufferSeconds
    case fmdxAudioMaxLatencySeconds
    case fmdxAudioPacketHoldSeconds
    case fmdxCustomScanSettleSeconds
    case fmdxCustomScanMetadataWindowSeconds
    case audioSuggestionScope
    case tuningGestureDirection
    case fmdxTuneConfirmationWarningsEnabled
    case openReceiverAfterHistoryRestore
    case showRecentFrequencies
    case includeRecentFrequenciesFromOtherReceivers
    case radiosSearchFiltersVisibility
    case autoConnectSelectedProfileOnLaunch
    case saveChannelScannerResultsEnabled
    case stopChannelScannerOnSignal
    case filterChannelScannerInterferenceEnabled
    case channelScannerInterferenceFilterProfile
    case saveFMDXScannerResultsEnabled
    case fmdxBandScanStartBehavior
    case fmdxBandScanHitBehavior
  }

  init(
    frequencyHz: Int,
    tuneStepHz: Int,
    preferredTuneStepHz: Int,
    tuneStepPreferenceMode: TuneStepPreferenceMode = .manual,
    mode: DemodulationMode,
    rfGain: Double,
    audioVolume: Double,
    audioMuted: Bool,
    mixWithOtherAudioApps: Bool = false,
    agcEnabled: Bool,
    imsEnabled: Bool,
    noiseReductionEnabled: Bool,
    squelchEnabled: Bool,
    openWebRXSquelchLevel: Int,
    kiwiSquelchThreshold: Int,
    kiwiNoiseBlankerAlgorithm: KiwiNoiseBlankerAlgorithm,
    kiwiNoiseBlankerGate: Int,
    kiwiNoiseBlankerThreshold: Int,
    kiwiNoiseBlankerWildThreshold: Double,
    kiwiNoiseBlankerWildTaps: Int,
    kiwiNoiseBlankerWildImpulseSamples: Int,
    kiwiNoiseFilterAlgorithm: KiwiNoiseFilterAlgorithm,
    kiwiDenoiseEnabled: Bool,
    kiwiAutonotchEnabled: Bool,
    kiwiPassbandsByMode: [String: ReceiverBandpass],
    kiwiWaterfallSpeed: Int,
    kiwiWaterfallWindowFunction: Int,
    kiwiWaterfallInterpolation: Int,
    kiwiWaterfallCICCompensation: Bool,
    kiwiWaterfallZoom: Int,
    kiwiWaterfallPanOffsetBins: Int,
    kiwiWaterfallMinDB: Int,
    kiwiWaterfallMaxDB: Int,
    showRdsErrorCounters: Bool,
    voiceOverRDSAnnouncementMode: VoiceOverRDSAnnouncementMode,
    magicTapAction: MagicTapAction = Self.default.magicTapAction,
    accessibilityInteractionSoundsEnabled: Bool = Self.default.accessibilityInteractionSoundsEnabled,
    accessibilityInteractionSoundsVolume: Double = Self.default.accessibilityInteractionSoundsVolume,
    accessibilityInteractionSoundsMutedDuringRecording: Bool = Self.default.accessibilityInteractionSoundsMutedDuringRecording,
    accessibilitySelectionAnnouncementsEnabled: Bool = Self.default.accessibilitySelectionAnnouncementsEnabled,
    accessibilityConnectionSoundsEnabled: Bool = Self.default.accessibilityConnectionSoundsEnabled,
    accessibilityRecordingSoundsEnabled: Bool = Self.default.accessibilityRecordingSoundsEnabled,
    accessibilitySpeechLoudnessLevelingEnabled: Bool = Self.default.accessibilitySpeechLoudnessLevelingEnabled,
    showTutorialOnLaunchEnabled: Bool = Self.default.showTutorialOnLaunchEnabled,
    rememberSquelchOnConnectEnabled: Bool = Self.default.rememberSquelchOnConnectEnabled,
    dxNightModeEnabled: Bool,
    autoFilterProfileEnabled: Bool,
    adaptiveScannerEnabled: Bool,
    scannerDwellSeconds: Double,
    scannerHoldSeconds: Double,
    playDetectedChannelScannerSignalsEnabled: Bool = true,
    fmdxAudioStartupBufferSeconds: Double,
    fmdxAudioMaxLatencySeconds: Double,
    fmdxAudioPacketHoldSeconds: Double,
    fmdxCustomScanSettleSeconds: Double = 0.16,
    fmdxCustomScanMetadataWindowSeconds: Double = 0.90,
    audioSuggestionScope: AudioSuggestionScope,
    tuningGestureDirection: TuningGestureDirection,
    fmdxTuneConfirmationWarningsEnabled: Bool = false,
    openReceiverAfterHistoryRestore: Bool,
    showRecentFrequencies: Bool = Self.default.showRecentFrequencies,
    includeRecentFrequenciesFromOtherReceivers: Bool = Self.default.includeRecentFrequenciesFromOtherReceivers,
    radiosSearchFiltersVisibility: RadiosSearchFiltersVisibility = Self.default.radiosSearchFiltersVisibility,
    autoConnectSelectedProfileOnLaunch: Bool,
    saveChannelScannerResultsEnabled: Bool = Self.default.saveChannelScannerResultsEnabled,
    stopChannelScannerOnSignal: Bool = Self.default.stopChannelScannerOnSignal,
    filterChannelScannerInterferenceEnabled: Bool = Self.default.filterChannelScannerInterferenceEnabled,
    channelScannerInterferenceFilterProfile: ChannelScannerInterferenceFilterProfile = Self.default.channelScannerInterferenceFilterProfile,
    saveFMDXScannerResultsEnabled: Bool = false,
    fmdxBandScanStartBehavior: FMDXBandScanStartBehavior = .fromBeginning,
    fmdxBandScanHitBehavior: FMDXBandScanHitBehavior = .continuous
  ) {
    self.frequencyHz = frequencyHz
    self.tuneStepHz = Self.normalizedTuneStep(tuneStepHz)
    self.preferredTuneStepHz = Self.normalizedTuneStep(preferredTuneStepHz)
    self.tuneStepPreferenceMode = tuneStepPreferenceMode
    self.mode = mode
    self.rfGain = rfGain
    self.audioVolume = audioVolume
    self.audioMuted = audioMuted
    self.mixWithOtherAudioApps = mixWithOtherAudioApps
    self.agcEnabled = agcEnabled
    self.imsEnabled = imsEnabled
    self.noiseReductionEnabled = noiseReductionEnabled
    self.squelchEnabled = squelchEnabled
    self.openWebRXSquelchLevel = Self.clampedOpenWebRXSquelchLevel(openWebRXSquelchLevel)
    self.kiwiSquelchThreshold = Self.clampedKiwiSquelchThreshold(kiwiSquelchThreshold)
    self.kiwiNoiseBlankerAlgorithm = kiwiNoiseBlankerAlgorithm
    self.kiwiNoiseBlankerGate = Self.clampedKiwiNoiseBlankerGate(kiwiNoiseBlankerGate)
    self.kiwiNoiseBlankerThreshold = Self.clampedKiwiNoiseBlankerThreshold(kiwiNoiseBlankerThreshold)
    self.kiwiNoiseBlankerWildThreshold = Self.clampedKiwiNoiseBlankerWildThreshold(kiwiNoiseBlankerWildThreshold)
    self.kiwiNoiseBlankerWildTaps = Self.clampedKiwiNoiseBlankerWildTaps(kiwiNoiseBlankerWildTaps)
    self.kiwiNoiseBlankerWildImpulseSamples = Self.clampedKiwiNoiseBlankerWildImpulseSamples(kiwiNoiseBlankerWildImpulseSamples)
    self.kiwiNoiseFilterAlgorithm = kiwiNoiseFilterAlgorithm
    self.kiwiDenoiseEnabled = kiwiNoiseFilterAlgorithm == .spectral ? true : kiwiDenoiseEnabled
    self.kiwiAutonotchEnabled = kiwiNoiseFilterAlgorithm == .spectral ? false : kiwiAutonotchEnabled
    if (self.kiwiNoiseFilterAlgorithm == .wdsp || self.kiwiNoiseFilterAlgorithm == .original),
      self.kiwiDenoiseEnabled == false,
      self.kiwiAutonotchEnabled == false {
      self.kiwiDenoiseEnabled = true
    }
    self.kiwiPassbandsByMode = [:]
    for (rawMode, bandpass) in kiwiPassbandsByMode {
      let normalizedMode = DemodulationMode(rawValue: rawMode)?.normalized(for: .kiwiSDR) ?? .am
      self.kiwiPassbandsByMode[normalizedMode.rawValue] = Self.normalizedKiwiBandpass(
        bandpass,
        mode: normalizedMode,
        sampleRateHz: nil
      )
    }
    self.kiwiWaterfallSpeed = Self.normalizedKiwiWaterfallSpeed(kiwiWaterfallSpeed)
    self.kiwiWaterfallWindowFunction = Self.normalizedKiwiWaterfallWindowFunction(kiwiWaterfallWindowFunction)
    self.kiwiWaterfallInterpolation = Self.normalizedKiwiWaterfallInterpolation(kiwiWaterfallInterpolation)
    self.kiwiWaterfallCICCompensation = kiwiWaterfallCICCompensation
    self.kiwiWaterfallZoom = Self.clampedKiwiWaterfallZoom(kiwiWaterfallZoom)
    self.kiwiWaterfallPanOffsetBins = Self.clampedKiwiWaterfallPanOffsetBins(kiwiWaterfallPanOffsetBins)
    self.kiwiWaterfallMinDB = Self.clampedKiwiWaterfallMinDB(kiwiWaterfallMinDB)
    self.kiwiWaterfallMaxDB = Self.clampedKiwiWaterfallMaxDB(kiwiWaterfallMaxDB)
    if self.kiwiWaterfallMaxDB <= self.kiwiWaterfallMinDB {
      self.kiwiWaterfallMaxDB = min(0, self.kiwiWaterfallMinDB + 10)
    }
    self.showRdsErrorCounters = showRdsErrorCounters
    self.voiceOverRDSAnnouncementMode = voiceOverRDSAnnouncementMode
    self.magicTapAction = magicTapAction
    self.accessibilityInteractionSoundsEnabled = accessibilityInteractionSoundsEnabled
    self.accessibilityInteractionSoundsVolume = Self.clampedAccessibilityInteractionSoundsVolume(
      accessibilityInteractionSoundsVolume
    )
    self.accessibilityInteractionSoundsMutedDuringRecording = accessibilityInteractionSoundsMutedDuringRecording
    self.accessibilitySelectionAnnouncementsEnabled = accessibilitySelectionAnnouncementsEnabled
    self.accessibilityConnectionSoundsEnabled = accessibilityConnectionSoundsEnabled
    self.accessibilityRecordingSoundsEnabled = accessibilityRecordingSoundsEnabled
    self.accessibilitySpeechLoudnessLevelingEnabled = accessibilitySpeechLoudnessLevelingEnabled
    self.showTutorialOnLaunchEnabled = showTutorialOnLaunchEnabled
    self.rememberSquelchOnConnectEnabled = rememberSquelchOnConnectEnabled
    self.dxNightModeEnabled = dxNightModeEnabled
    self.autoFilterProfileEnabled = autoFilterProfileEnabled
    self.adaptiveScannerEnabled = adaptiveScannerEnabled
    self.scannerDwellSeconds = Self.clampedScannerDwellSeconds(scannerDwellSeconds)
    self.scannerHoldSeconds = Self.clampedScannerHoldSeconds(scannerHoldSeconds)
    self.playDetectedChannelScannerSignalsEnabled = playDetectedChannelScannerSignalsEnabled
    self.fmdxAudioStartupBufferSeconds = Self.clampedFMDXAudioStartupBufferSeconds(fmdxAudioStartupBufferSeconds)
    self.fmdxAudioMaxLatencySeconds = Self.clampedFMDXAudioMaxLatencySeconds(
      fmdxAudioMaxLatencySeconds,
      startupBufferSeconds: self.fmdxAudioStartupBufferSeconds
    )
    self.fmdxAudioPacketHoldSeconds = Self.clampedFMDXAudioPacketHoldSeconds(fmdxAudioPacketHoldSeconds)
    self.fmdxCustomScanSettleSeconds = Self.clampedFMDXCustomScanSettleSeconds(fmdxCustomScanSettleSeconds)
    self.fmdxCustomScanMetadataWindowSeconds = Self.clampedFMDXCustomScanMetadataWindowSeconds(fmdxCustomScanMetadataWindowSeconds)
    self.audioSuggestionScope = audioSuggestionScope
    self.tuningGestureDirection = tuningGestureDirection
    self.fmdxTuneConfirmationWarningsEnabled = fmdxTuneConfirmationWarningsEnabled
    self.openReceiverAfterHistoryRestore = openReceiverAfterHistoryRestore
    self.showRecentFrequencies = showRecentFrequencies
    self.includeRecentFrequenciesFromOtherReceivers = includeRecentFrequenciesFromOtherReceivers
    self.radiosSearchFiltersVisibility = radiosSearchFiltersVisibility
    self.autoConnectSelectedProfileOnLaunch = autoConnectSelectedProfileOnLaunch
    self.saveChannelScannerResultsEnabled = saveChannelScannerResultsEnabled
    self.stopChannelScannerOnSignal = stopChannelScannerOnSignal
    self.filterChannelScannerInterferenceEnabled = filterChannelScannerInterferenceEnabled
    self.channelScannerInterferenceFilterProfile = channelScannerInterferenceFilterProfile
    self.saveFMDXScannerResultsEnabled = saveFMDXScannerResultsEnabled
    self.fmdxBandScanStartBehavior = fmdxBandScanStartBehavior
    self.fmdxBandScanHitBehavior = fmdxBandScanHitBehavior
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    frequencyHz = try container.decodeIfPresent(Int.self, forKey: .frequencyHz) ?? Self.default.frequencyHz
    let rawTuneStepHz = try container.decodeIfPresent(Int.self, forKey: .tuneStepHz) ?? Self.default.tuneStepHz
    tuneStepHz = Self.normalizedTuneStep(rawTuneStepHz)
    let rawPreferredTuneStepHz = try container.decodeIfPresent(Int.self, forKey: .preferredTuneStepHz) ?? rawTuneStepHz
    preferredTuneStepHz = Self.normalizedTuneStep(rawPreferredTuneStepHz)
    tuneStepPreferenceMode =
      try container.decodeIfPresent(TuneStepPreferenceMode.self, forKey: .tuneStepPreferenceMode)
      ?? Self.default.tuneStepPreferenceMode
    mode = try container.decodeIfPresent(DemodulationMode.self, forKey: .mode) ?? Self.default.mode
    rfGain = try container.decodeIfPresent(Double.self, forKey: .rfGain) ?? Self.default.rfGain
    audioVolume = try container.decodeIfPresent(Double.self, forKey: .audioVolume) ?? Self.default.audioVolume
    audioMuted = try container.decodeIfPresent(Bool.self, forKey: .audioMuted) ?? Self.default.audioMuted
    mixWithOtherAudioApps =
      try container.decodeIfPresent(Bool.self, forKey: .mixWithOtherAudioApps)
      ?? Self.default.mixWithOtherAudioApps
    agcEnabled = try container.decodeIfPresent(Bool.self, forKey: .agcEnabled) ?? Self.default.agcEnabled
    imsEnabled = try container.decodeIfPresent(Bool.self, forKey: .imsEnabled) ?? Self.default.imsEnabled
    noiseReductionEnabled = try container.decodeIfPresent(Bool.self, forKey: .noiseReductionEnabled) ?? Self.default.noiseReductionEnabled
    squelchEnabled = try container.decodeIfPresent(Bool.self, forKey: .squelchEnabled) ?? Self.default.squelchEnabled

    let rawOpenWebRXSquelchLevel = try container.decodeIfPresent(Int.self, forKey: .openWebRXSquelchLevel)
      ?? Self.default.openWebRXSquelchLevel
    openWebRXSquelchLevel = Self.clampedOpenWebRXSquelchLevel(rawOpenWebRXSquelchLevel)

    let rawKiwiSquelchThreshold = try container.decodeIfPresent(Int.self, forKey: .kiwiSquelchThreshold)
      ?? Self.default.kiwiSquelchThreshold
    kiwiSquelchThreshold = Self.clampedKiwiSquelchThreshold(rawKiwiSquelchThreshold)

    kiwiNoiseBlankerAlgorithm =
      try container.decodeIfPresent(KiwiNoiseBlankerAlgorithm.self, forKey: .kiwiNoiseBlankerAlgorithm)
      ?? Self.default.kiwiNoiseBlankerAlgorithm
    kiwiNoiseBlankerGate = Self.clampedKiwiNoiseBlankerGate(
      try container.decodeIfPresent(Int.self, forKey: .kiwiNoiseBlankerGate)
        ?? Self.default.kiwiNoiseBlankerGate
    )
    kiwiNoiseBlankerThreshold = Self.clampedKiwiNoiseBlankerThreshold(
      try container.decodeIfPresent(Int.self, forKey: .kiwiNoiseBlankerThreshold)
        ?? Self.default.kiwiNoiseBlankerThreshold
    )
    kiwiNoiseBlankerWildThreshold = Self.clampedKiwiNoiseBlankerWildThreshold(
      try container.decodeIfPresent(Double.self, forKey: .kiwiNoiseBlankerWildThreshold)
        ?? Self.default.kiwiNoiseBlankerWildThreshold
    )
    kiwiNoiseBlankerWildTaps = Self.clampedKiwiNoiseBlankerWildTaps(
      try container.decodeIfPresent(Int.self, forKey: .kiwiNoiseBlankerWildTaps)
        ?? Self.default.kiwiNoiseBlankerWildTaps
    )
    kiwiNoiseBlankerWildImpulseSamples = Self.clampedKiwiNoiseBlankerWildImpulseSamples(
      try container.decodeIfPresent(Int.self, forKey: .kiwiNoiseBlankerWildImpulseSamples)
        ?? Self.default.kiwiNoiseBlankerWildImpulseSamples
    )
    kiwiNoiseFilterAlgorithm =
      try container.decodeIfPresent(KiwiNoiseFilterAlgorithm.self, forKey: .kiwiNoiseFilterAlgorithm)
      ?? Self.default.kiwiNoiseFilterAlgorithm
    kiwiDenoiseEnabled = try container.decodeIfPresent(Bool.self, forKey: .kiwiDenoiseEnabled)
      ?? Self.default.kiwiDenoiseEnabled
    kiwiAutonotchEnabled = try container.decodeIfPresent(Bool.self, forKey: .kiwiAutonotchEnabled)
      ?? Self.default.kiwiAutonotchEnabled
    if kiwiNoiseFilterAlgorithm == .spectral {
      kiwiDenoiseEnabled = true
      kiwiAutonotchEnabled = false
    } else if (kiwiNoiseFilterAlgorithm == .wdsp || kiwiNoiseFilterAlgorithm == .original),
      kiwiDenoiseEnabled == false,
      kiwiAutonotchEnabled == false {
      kiwiDenoiseEnabled = true
    }

    let rawKiwiPassbandsByMode = try container.decodeIfPresent([String: ReceiverBandpass].self, forKey: .kiwiPassbandsByMode)
      ?? Self.default.kiwiPassbandsByMode
    kiwiPassbandsByMode = [:]
    for (rawMode, bandpass) in rawKiwiPassbandsByMode {
      let normalizedMode = DemodulationMode(rawValue: rawMode)?.normalized(for: .kiwiSDR) ?? .am
      kiwiPassbandsByMode[normalizedMode.rawValue] = Self.normalizedKiwiBandpass(
        bandpass,
        mode: normalizedMode,
        sampleRateHz: nil
      )
    }

    let rawKiwiWaterfallSpeed = try container.decodeIfPresent(Int.self, forKey: .kiwiWaterfallSpeed)
      ?? Self.default.kiwiWaterfallSpeed
    kiwiWaterfallSpeed = Self.normalizedKiwiWaterfallSpeed(rawKiwiWaterfallSpeed)

    let rawKiwiWaterfallWindowFunction = try container.decodeIfPresent(Int.self, forKey: .kiwiWaterfallWindowFunction)
      ?? Self.default.kiwiWaterfallWindowFunction
    kiwiWaterfallWindowFunction = Self.normalizedKiwiWaterfallWindowFunction(rawKiwiWaterfallWindowFunction)

    let rawKiwiWaterfallInterpolation = try container.decodeIfPresent(Int.self, forKey: .kiwiWaterfallInterpolation)
      ?? Self.default.kiwiWaterfallInterpolation
    kiwiWaterfallInterpolation = Self.normalizedKiwiWaterfallInterpolation(rawKiwiWaterfallInterpolation)

    kiwiWaterfallCICCompensation = try container.decodeIfPresent(Bool.self, forKey: .kiwiWaterfallCICCompensation)
      ?? Self.default.kiwiWaterfallCICCompensation

    let rawKiwiWaterfallZoom = try container.decodeIfPresent(Int.self, forKey: .kiwiWaterfallZoom)
      ?? Self.default.kiwiWaterfallZoom
    kiwiWaterfallZoom = Self.clampedKiwiWaterfallZoom(rawKiwiWaterfallZoom)
    kiwiWaterfallPanOffsetBins = Self.clampedKiwiWaterfallPanOffsetBins(
      try container.decodeIfPresent(Int.self, forKey: .kiwiWaterfallPanOffsetBins)
        ?? Self.default.kiwiWaterfallPanOffsetBins
    )

    let rawKiwiWaterfallMinDB = try container.decodeIfPresent(Int.self, forKey: .kiwiWaterfallMinDB)
      ?? Self.default.kiwiWaterfallMinDB
    let rawKiwiWaterfallMaxDB = try container.decodeIfPresent(Int.self, forKey: .kiwiWaterfallMaxDB)
      ?? Self.default.kiwiWaterfallMaxDB
    kiwiWaterfallMinDB = Self.clampedKiwiWaterfallMinDB(rawKiwiWaterfallMinDB)
    kiwiWaterfallMaxDB = Self.clampedKiwiWaterfallMaxDB(rawKiwiWaterfallMaxDB)
    if kiwiWaterfallMaxDB <= kiwiWaterfallMinDB {
      kiwiWaterfallMaxDB = min(0, kiwiWaterfallMinDB + 10)
    }

    showRdsErrorCounters = try container.decodeIfPresent(Bool.self, forKey: .showRdsErrorCounters) ?? Self.default.showRdsErrorCounters
    voiceOverRDSAnnouncementMode =
      try container.decodeIfPresent(VoiceOverRDSAnnouncementMode.self, forKey: .voiceOverRDSAnnouncementMode)
      ?? (
        (try container.decodeIfPresent(Bool.self, forKey: .voiceOverAnnouncesRDSChanges) ?? false)
          ? .full
          : Self.default.voiceOverRDSAnnouncementMode
      )
    magicTapAction = try container.decodeIfPresent(MagicTapAction.self, forKey: .magicTapAction)
      ?? Self.default.magicTapAction
    accessibilityInteractionSoundsEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .accessibilityInteractionSoundsEnabled)
      ?? Self.default.accessibilityInteractionSoundsEnabled
    accessibilityInteractionSoundsVolume = Self.clampedAccessibilityInteractionSoundsVolume(
      try container.decodeIfPresent(Double.self, forKey: .accessibilityInteractionSoundsVolume)
        ?? Self.default.accessibilityInteractionSoundsVolume
    )
    accessibilityInteractionSoundsMutedDuringRecording =
      try container.decodeIfPresent(Bool.self, forKey: .accessibilityInteractionSoundsMutedDuringRecording)
      ?? Self.default.accessibilityInteractionSoundsMutedDuringRecording
    accessibilitySelectionAnnouncementsEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .accessibilitySelectionAnnouncementsEnabled)
      ?? Self.default.accessibilitySelectionAnnouncementsEnabled
    accessibilityConnectionSoundsEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .accessibilityConnectionSoundsEnabled)
      ?? Self.default.accessibilityConnectionSoundsEnabled
    accessibilityRecordingSoundsEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .accessibilityRecordingSoundsEnabled)
      ?? Self.default.accessibilityRecordingSoundsEnabled
    accessibilitySpeechLoudnessLevelingEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .accessibilitySpeechLoudnessLevelingEnabled)
      ?? Self.default.accessibilitySpeechLoudnessLevelingEnabled
    showTutorialOnLaunchEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .showTutorialOnLaunchEnabled)
      ?? Self.default.showTutorialOnLaunchEnabled
    rememberSquelchOnConnectEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .rememberSquelchOnConnectEnabled)
      ?? Self.default.rememberSquelchOnConnectEnabled
    dxNightModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .dxNightModeEnabled) ?? Self.default.dxNightModeEnabled
    autoFilterProfileEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoFilterProfileEnabled) ?? Self.default.autoFilterProfileEnabled
    adaptiveScannerEnabled = try container.decodeIfPresent(Bool.self, forKey: .adaptiveScannerEnabled) ?? Self.default.adaptiveScannerEnabled

    let rawScannerDwellSeconds = try container.decodeIfPresent(Double.self, forKey: .scannerDwellSeconds)
      ?? Self.default.scannerDwellSeconds
    scannerDwellSeconds = Self.clampedScannerDwellSeconds(rawScannerDwellSeconds)

    let rawScannerHoldSeconds = try container.decodeIfPresent(Double.self, forKey: .scannerHoldSeconds)
      ?? Self.default.scannerHoldSeconds
    scannerHoldSeconds = Self.clampedScannerHoldSeconds(rawScannerHoldSeconds)
    playDetectedChannelScannerSignalsEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .playDetectedChannelScannerSignalsEnabled)
      ?? Self.default.playDetectedChannelScannerSignalsEnabled

    let rawFMDXStartupBufferSeconds = try container.decodeIfPresent(Double.self, forKey: .fmdxAudioStartupBufferSeconds)
      ?? Self.default.fmdxAudioStartupBufferSeconds
    fmdxAudioStartupBufferSeconds = Self.clampedFMDXAudioStartupBufferSeconds(rawFMDXStartupBufferSeconds)

    let rawFMDXMaxLatencySeconds = try container.decodeIfPresent(Double.self, forKey: .fmdxAudioMaxLatencySeconds)
      ?? Self.default.fmdxAudioMaxLatencySeconds
    fmdxAudioMaxLatencySeconds = Self.clampedFMDXAudioMaxLatencySeconds(
      rawFMDXMaxLatencySeconds,
      startupBufferSeconds: fmdxAudioStartupBufferSeconds
    )

    let rawFMDXPacketHoldSeconds = try container.decodeIfPresent(Double.self, forKey: .fmdxAudioPacketHoldSeconds)
      ?? Self.default.fmdxAudioPacketHoldSeconds
    fmdxAudioPacketHoldSeconds = Self.clampedFMDXAudioPacketHoldSeconds(rawFMDXPacketHoldSeconds)
    let rawFMDXCustomScanSettleSeconds = try container.decodeIfPresent(Double.self, forKey: .fmdxCustomScanSettleSeconds)
      ?? Self.default.fmdxCustomScanSettleSeconds
    fmdxCustomScanSettleSeconds = Self.clampedFMDXCustomScanSettleSeconds(rawFMDXCustomScanSettleSeconds)
    let rawFMDXCustomScanMetadataWindowSeconds = try container.decodeIfPresent(Double.self, forKey: .fmdxCustomScanMetadataWindowSeconds)
      ?? Self.default.fmdxCustomScanMetadataWindowSeconds
    fmdxCustomScanMetadataWindowSeconds = Self.clampedFMDXCustomScanMetadataWindowSeconds(rawFMDXCustomScanMetadataWindowSeconds)
    audioSuggestionScope = try container.decodeIfPresent(AudioSuggestionScope.self, forKey: .audioSuggestionScope)
      ?? Self.default.audioSuggestionScope
    tuningGestureDirection = try container.decodeIfPresent(TuningGestureDirection.self, forKey: .tuningGestureDirection)
      ?? Self.default.tuningGestureDirection
    fmdxTuneConfirmationWarningsEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .fmdxTuneConfirmationWarningsEnabled)
      ?? Self.default.fmdxTuneConfirmationWarningsEnabled
    openReceiverAfterHistoryRestore = try container.decodeIfPresent(Bool.self, forKey: .openReceiverAfterHistoryRestore)
      ?? Self.default.openReceiverAfterHistoryRestore
    showRecentFrequencies = try container.decodeIfPresent(Bool.self, forKey: .showRecentFrequencies)
      ?? Self.default.showRecentFrequencies
    includeRecentFrequenciesFromOtherReceivers =
      try container.decodeIfPresent(Bool.self, forKey: .includeRecentFrequenciesFromOtherReceivers)
      ?? Self.default.includeRecentFrequenciesFromOtherReceivers
    radiosSearchFiltersVisibility =
      try container.decodeIfPresent(RadiosSearchFiltersVisibility.self, forKey: .radiosSearchFiltersVisibility)
      ?? Self.default.radiosSearchFiltersVisibility
    autoConnectSelectedProfileOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .autoConnectSelectedProfileOnLaunch)
      ?? Self.default.autoConnectSelectedProfileOnLaunch
    saveChannelScannerResultsEnabled = try container.decodeIfPresent(Bool.self, forKey: .saveChannelScannerResultsEnabled)
      ?? Self.default.saveChannelScannerResultsEnabled
    stopChannelScannerOnSignal = try container.decodeIfPresent(Bool.self, forKey: .stopChannelScannerOnSignal)
      ?? Self.default.stopChannelScannerOnSignal
    filterChannelScannerInterferenceEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .filterChannelScannerInterferenceEnabled)
      ?? Self.default.filterChannelScannerInterferenceEnabled
    channelScannerInterferenceFilterProfile =
      try container.decodeIfPresent(
        ChannelScannerInterferenceFilterProfile.self,
        forKey: .channelScannerInterferenceFilterProfile
      )
      ?? Self.default.channelScannerInterferenceFilterProfile
    saveFMDXScannerResultsEnabled = try container.decodeIfPresent(Bool.self, forKey: .saveFMDXScannerResultsEnabled)
      ?? Self.default.saveFMDXScannerResultsEnabled
    fmdxBandScanStartBehavior =
      try container.decodeIfPresent(FMDXBandScanStartBehavior.self, forKey: .fmdxBandScanStartBehavior)
      ?? Self.default.fmdxBandScanStartBehavior
    fmdxBandScanHitBehavior =
      try container.decodeIfPresent(FMDXBandScanHitBehavior.self, forKey: .fmdxBandScanHitBehavior)
      ?? Self.default.fmdxBandScanHitBehavior
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(frequencyHz, forKey: .frequencyHz)
    try container.encode(tuneStepHz, forKey: .tuneStepHz)
    try container.encode(preferredTuneStepHz, forKey: .preferredTuneStepHz)
    try container.encode(tuneStepPreferenceMode, forKey: .tuneStepPreferenceMode)
    try container.encode(mode, forKey: .mode)
    try container.encode(rfGain, forKey: .rfGain)
    try container.encode(audioVolume, forKey: .audioVolume)
    try container.encode(audioMuted, forKey: .audioMuted)
    try container.encode(mixWithOtherAudioApps, forKey: .mixWithOtherAudioApps)
    try container.encode(agcEnabled, forKey: .agcEnabled)
    try container.encode(imsEnabled, forKey: .imsEnabled)
    try container.encode(noiseReductionEnabled, forKey: .noiseReductionEnabled)
    try container.encode(squelchEnabled, forKey: .squelchEnabled)
    try container.encode(openWebRXSquelchLevel, forKey: .openWebRXSquelchLevel)
    try container.encode(kiwiSquelchThreshold, forKey: .kiwiSquelchThreshold)
    try container.encode(kiwiNoiseBlankerAlgorithm, forKey: .kiwiNoiseBlankerAlgorithm)
    try container.encode(kiwiNoiseBlankerGate, forKey: .kiwiNoiseBlankerGate)
    try container.encode(kiwiNoiseBlankerThreshold, forKey: .kiwiNoiseBlankerThreshold)
    try container.encode(kiwiNoiseBlankerWildThreshold, forKey: .kiwiNoiseBlankerWildThreshold)
    try container.encode(kiwiNoiseBlankerWildTaps, forKey: .kiwiNoiseBlankerWildTaps)
    try container.encode(kiwiNoiseBlankerWildImpulseSamples, forKey: .kiwiNoiseBlankerWildImpulseSamples)
    try container.encode(kiwiNoiseFilterAlgorithm, forKey: .kiwiNoiseFilterAlgorithm)
    try container.encode(kiwiDenoiseEnabled, forKey: .kiwiDenoiseEnabled)
    try container.encode(kiwiAutonotchEnabled, forKey: .kiwiAutonotchEnabled)
    try container.encode(kiwiPassbandsByMode, forKey: .kiwiPassbandsByMode)
    try container.encode(kiwiWaterfallSpeed, forKey: .kiwiWaterfallSpeed)
    try container.encode(kiwiWaterfallWindowFunction, forKey: .kiwiWaterfallWindowFunction)
    try container.encode(kiwiWaterfallInterpolation, forKey: .kiwiWaterfallInterpolation)
    try container.encode(kiwiWaterfallCICCompensation, forKey: .kiwiWaterfallCICCompensation)
    try container.encode(kiwiWaterfallZoom, forKey: .kiwiWaterfallZoom)
    try container.encode(kiwiWaterfallPanOffsetBins, forKey: .kiwiWaterfallPanOffsetBins)
    try container.encode(kiwiWaterfallMinDB, forKey: .kiwiWaterfallMinDB)
    try container.encode(kiwiWaterfallMaxDB, forKey: .kiwiWaterfallMaxDB)
    try container.encode(showRdsErrorCounters, forKey: .showRdsErrorCounters)
    try container.encode(voiceOverRDSAnnouncementMode, forKey: .voiceOverRDSAnnouncementMode)
    try container.encode(magicTapAction, forKey: .magicTapAction)
    try container.encode(accessibilityInteractionSoundsEnabled, forKey: .accessibilityInteractionSoundsEnabled)
    try container.encode(accessibilityInteractionSoundsVolume, forKey: .accessibilityInteractionSoundsVolume)
    try container.encode(accessibilityInteractionSoundsMutedDuringRecording, forKey: .accessibilityInteractionSoundsMutedDuringRecording)
    try container.encode(accessibilitySelectionAnnouncementsEnabled, forKey: .accessibilitySelectionAnnouncementsEnabled)
    try container.encode(accessibilityConnectionSoundsEnabled, forKey: .accessibilityConnectionSoundsEnabled)
    try container.encode(accessibilityRecordingSoundsEnabled, forKey: .accessibilityRecordingSoundsEnabled)
    try container.encode(accessibilitySpeechLoudnessLevelingEnabled, forKey: .accessibilitySpeechLoudnessLevelingEnabled)
    try container.encode(showTutorialOnLaunchEnabled, forKey: .showTutorialOnLaunchEnabled)
    try container.encode(rememberSquelchOnConnectEnabled, forKey: .rememberSquelchOnConnectEnabled)
    try container.encode(dxNightModeEnabled, forKey: .dxNightModeEnabled)
    try container.encode(autoFilterProfileEnabled, forKey: .autoFilterProfileEnabled)
    try container.encode(adaptiveScannerEnabled, forKey: .adaptiveScannerEnabled)
    try container.encode(scannerDwellSeconds, forKey: .scannerDwellSeconds)
    try container.encode(scannerHoldSeconds, forKey: .scannerHoldSeconds)
    try container.encode(playDetectedChannelScannerSignalsEnabled, forKey: .playDetectedChannelScannerSignalsEnabled)
    try container.encode(fmdxAudioStartupBufferSeconds, forKey: .fmdxAudioStartupBufferSeconds)
    try container.encode(fmdxAudioMaxLatencySeconds, forKey: .fmdxAudioMaxLatencySeconds)
    try container.encode(fmdxAudioPacketHoldSeconds, forKey: .fmdxAudioPacketHoldSeconds)
    try container.encode(fmdxCustomScanSettleSeconds, forKey: .fmdxCustomScanSettleSeconds)
    try container.encode(fmdxCustomScanMetadataWindowSeconds, forKey: .fmdxCustomScanMetadataWindowSeconds)
    try container.encode(audioSuggestionScope, forKey: .audioSuggestionScope)
    try container.encode(tuningGestureDirection, forKey: .tuningGestureDirection)
    try container.encode(fmdxTuneConfirmationWarningsEnabled, forKey: .fmdxTuneConfirmationWarningsEnabled)
    try container.encode(openReceiverAfterHistoryRestore, forKey: .openReceiverAfterHistoryRestore)
    try container.encode(showRecentFrequencies, forKey: .showRecentFrequencies)
    try container.encode(
      includeRecentFrequenciesFromOtherReceivers,
      forKey: .includeRecentFrequenciesFromOtherReceivers
    )
    try container.encode(radiosSearchFiltersVisibility, forKey: .radiosSearchFiltersVisibility)
    try container.encode(autoConnectSelectedProfileOnLaunch, forKey: .autoConnectSelectedProfileOnLaunch)
    try container.encode(saveChannelScannerResultsEnabled, forKey: .saveChannelScannerResultsEnabled)
    try container.encode(stopChannelScannerOnSignal, forKey: .stopChannelScannerOnSignal)
    try container.encode(filterChannelScannerInterferenceEnabled, forKey: .filterChannelScannerInterferenceEnabled)
    try container.encode(channelScannerInterferenceFilterProfile, forKey: .channelScannerInterferenceFilterProfile)
    try container.encode(saveFMDXScannerResultsEnabled, forKey: .saveFMDXScannerResultsEnabled)
    try container.encode(fmdxBandScanStartBehavior, forKey: .fmdxBandScanStartBehavior)
    try container.encode(fmdxBandScanHitBehavior, forKey: .fmdxBandScanHitBehavior)
  }

  static func normalizedTuneStep(_ value: Int) -> Int {
    if supportedTuneStepsHz.contains(value) {
      return value
    }
    return supportedTuneStepsHz.min(by: { abs($0 - value) < abs($1 - value) }) ?? Self.default.tuneStepHz
  }

  static func clampedOpenWebRXSquelchLevel(_ value: Int) -> Int {
    min(max(value, -150), -20)
  }

  static func clampedKiwiSquelchThreshold(_ value: Int) -> Int {
    min(max(value, 0), 30)
  }

  static func clampedKiwiNoiseBlankerGate(_ value: Int) -> Int {
    let clamped = min(max(value, 100), 5_000)
    return (clamped / 100) * 100
  }

  static func clampedKiwiNoiseBlankerThreshold(_ value: Int) -> Int {
    min(max(value, 0), 100)
  }

  static func clampedKiwiNoiseBlankerWildThreshold(_ value: Double) -> Double {
    let clamped = min(max(value, 0.05), 3.0)
    return (clamped * 20).rounded() / 20
  }

  static func clampedKiwiNoiseBlankerWildTaps(_ value: Int) -> Int {
    min(max(value, 6), 40)
  }

  static func clampedKiwiNoiseBlankerWildImpulseSamples(_ value: Int) -> Int {
    var clamped = min(max(value, 3), 41)
    if clamped % 2 == 0 {
      clamped += clamped == 41 ? -1 : 1
    }
    return clamped
  }

  static func clampedKiwiWaterfallPanOffsetBins(_ value: Int) -> Int {
    min(max(value, -50_000_000), 50_000_000)
  }

  static let kiwiMinimumPassbandHz = KiwiPassbandCore.minimumPassbandHz

  static func kiwiPassbandLimitHz(sampleRateHz: Int?) -> Int {
    KiwiPassbandCore.passbandLimitHz(sampleRateHz: sampleRateHz)
  }

  static func normalizedKiwiBandpass(
    _ bandpass: ReceiverBandpass,
    mode: DemodulationMode,
    sampleRateHz: Int?
  ) -> ReceiverBandpass {
    KiwiPassbandCore.normalizedBandpass(
      bandpass,
      mode: mode,
      sampleRateHz: sampleRateHz
    )
  }

  func kiwiPassband(for mode: DemodulationMode, sampleRateHz: Int?) -> ReceiverBandpass {
    let normalizedMode = mode.normalized(for: .kiwiSDR)
    return KiwiPassbandCore.resolvedBandpass(
      storedBandpass: kiwiPassbandsByMode[normalizedMode.rawValue],
      mode: normalizedMode,
      sampleRateHz: sampleRateHz
    )
  }

  mutating func setKiwiPassband(
    _ bandpass: ReceiverBandpass,
    for mode: DemodulationMode,
    sampleRateHz: Int?
  ) {
    let normalizedMode = mode.normalized(for: .kiwiSDR)
    kiwiPassbandsByMode[normalizedMode.rawValue] = Self.normalizedKiwiBandpass(
      bandpass,
      mode: normalizedMode,
      sampleRateHz: sampleRateHz
    )
  }

  mutating func resetKiwiPassband(for mode: DemodulationMode) {
    kiwiPassbandsByMode.removeValue(forKey: mode.normalized(for: .kiwiSDR).rawValue)
  }

  mutating func resetKiwiNoiseBlanker() {
    kiwiNoiseBlankerAlgorithm = Self.default.kiwiNoiseBlankerAlgorithm
    kiwiNoiseBlankerGate = Self.default.kiwiNoiseBlankerGate
    kiwiNoiseBlankerThreshold = Self.default.kiwiNoiseBlankerThreshold
    kiwiNoiseBlankerWildThreshold = Self.default.kiwiNoiseBlankerWildThreshold
    kiwiNoiseBlankerWildTaps = Self.default.kiwiNoiseBlankerWildTaps
    kiwiNoiseBlankerWildImpulseSamples = Self.default.kiwiNoiseBlankerWildImpulseSamples
  }

  mutating func resetKiwiNoiseFilter() {
    kiwiNoiseFilterAlgorithm = Self.default.kiwiNoiseFilterAlgorithm
    kiwiDenoiseEnabled = Self.default.kiwiDenoiseEnabled
    kiwiAutonotchEnabled = Self.default.kiwiAutonotchEnabled
  }

  static func normalizedKiwiWaterfallSpeed(_ value: Int) -> Int {
    if value == 8 {
      return KiwiWaterfallRate.fast.rawValue
    }
    let options = KiwiWaterfallRate.allCases.map(\.rawValue)
    if options.contains(value) {
      return value
    }
    return options.min(by: { abs($0 - value) < abs($1 - value) }) ?? Self.default.kiwiWaterfallSpeed
  }

  static func normalizedKiwiWaterfallWindowFunction(_ value: Int) -> Int {
    let options = KiwiWaterfallWindowFunction.allCases.map(\.rawValue)
    if options.contains(value) {
      return value
    }
    return options.min(by: { abs($0 - value) < abs($1 - value) }) ?? Self.default.kiwiWaterfallWindowFunction
  }

  static func normalizedKiwiWaterfallInterpolation(_ value: Int) -> Int {
    let options = KiwiWaterfallInterpolation.allCases.map(\.rawValue)
    if options.contains(value) {
      return value
    }
    return options.min(by: { abs($0 - value) < abs($1 - value) }) ?? Self.default.kiwiWaterfallInterpolation
  }

  static func clampedKiwiWaterfallZoom(_ value: Int) -> Int {
    min(max(value, 0), 14)
  }

  static func clampedKiwiWaterfallMinDB(_ value: Int) -> Int {
    min(max(value, -190), -10)
  }

  static func clampedKiwiWaterfallMaxDB(_ value: Int) -> Int {
    min(max(value, -120), 30)
  }

  static func clampedScannerDwellSeconds(_ value: Double) -> Double {
    min(max(value, 0.5), 6.0)
  }

  static func clampedScannerHoldSeconds(_ value: Double) -> Double {
    min(max(value, 0.5), 12.0)
  }

  static func clampedFMDXAudioStartupBufferSeconds(_ value: Double) -> Double {
    min(max(value, 0.25), 1.5)
  }

  static func clampedFMDXAudioMaxLatencySeconds(_ value: Double, startupBufferSeconds: Double) -> Double {
    let clamped = min(max(value, 0.6), 3.0)
    let minimum = min(3.0, startupBufferSeconds + 0.25)
    return max(clamped, minimum)
  }

  static func clampedFMDXAudioPacketHoldSeconds(_ value: Double) -> Double {
    min(max(value, 0.05), 0.35)
  }

  static func clampedFMDXCustomScanSettleSeconds(_ value: Double) -> Double {
    min(max(value, 0.05), 0.60)
  }

  static func clampedFMDXCustomScanMetadataWindowSeconds(_ value: Double) -> Double {
    min(max(value, 0.0), 2.0)
  }

  static func clampedAccessibilityInteractionSoundsVolume(_ value: Double) -> Double {
    let clamped = min(max(value, 0.5), 2.5)
    return (clamped * 20).rounded() / 20
  }
}
