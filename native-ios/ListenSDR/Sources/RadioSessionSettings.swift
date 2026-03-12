import Foundation

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
  var mode: DemodulationMode
  var rfGain: Double
  var audioVolume: Double
  var audioMuted: Bool
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
  var dxNightModeEnabled: Bool
  var autoFilterProfileEnabled: Bool
  var adaptiveScannerEnabled: Bool
  var scannerDwellSeconds: Double
  var scannerHoldSeconds: Double
  var fmdxAudioStartupBufferSeconds: Double
  var fmdxAudioMaxLatencySeconds: Double
  var fmdxAudioPacketHoldSeconds: Double
  var audioSuggestionScope: AudioSuggestionScope
  var tuningGestureDirection: TuningGestureDirection
  var openReceiverAfterHistoryRestore: Bool

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
    mode: .am,
    rfGain: 30,
    audioVolume: 0.85,
    audioMuted: false,
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
    dxNightModeEnabled: false,
    autoFilterProfileEnabled: false,
    adaptiveScannerEnabled: false,
    scannerDwellSeconds: 1.5,
    scannerHoldSeconds: 4.0,
    fmdxAudioStartupBufferSeconds: 0.55,
    fmdxAudioMaxLatencySeconds: 1.8,
    fmdxAudioPacketHoldSeconds: 0.14,
    audioSuggestionScope: .fmDxOnly,
    tuningGestureDirection: .natural,
    openReceiverAfterHistoryRestore: false
  )

  private enum CodingKeys: String, CodingKey {
    case frequencyHz
    case tuneStepHz
    case preferredTuneStepHz
    case mode
    case rfGain
    case audioVolume
    case audioMuted
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
    case dxNightModeEnabled
    case autoFilterProfileEnabled
    case adaptiveScannerEnabled
    case scannerDwellSeconds
    case scannerHoldSeconds
    case fmdxAudioStartupBufferSeconds
    case fmdxAudioMaxLatencySeconds
    case fmdxAudioPacketHoldSeconds
    case audioSuggestionScope
    case tuningGestureDirection
    case openReceiverAfterHistoryRestore
  }

  init(
    frequencyHz: Int,
    tuneStepHz: Int,
    preferredTuneStepHz: Int,
    mode: DemodulationMode,
    rfGain: Double,
    audioVolume: Double,
    audioMuted: Bool,
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
    dxNightModeEnabled: Bool,
    autoFilterProfileEnabled: Bool,
    adaptiveScannerEnabled: Bool,
    scannerDwellSeconds: Double,
    scannerHoldSeconds: Double,
    fmdxAudioStartupBufferSeconds: Double,
    fmdxAudioMaxLatencySeconds: Double,
    fmdxAudioPacketHoldSeconds: Double,
    audioSuggestionScope: AudioSuggestionScope,
    tuningGestureDirection: TuningGestureDirection,
    openReceiverAfterHistoryRestore: Bool
  ) {
    self.frequencyHz = frequencyHz
    self.tuneStepHz = Self.normalizedTuneStep(tuneStepHz)
    self.preferredTuneStepHz = Self.normalizedTuneStep(preferredTuneStepHz)
    self.mode = mode
    self.rfGain = rfGain
    self.audioVolume = audioVolume
    self.audioMuted = audioMuted
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
    self.dxNightModeEnabled = dxNightModeEnabled
    self.autoFilterProfileEnabled = autoFilterProfileEnabled
    self.adaptiveScannerEnabled = adaptiveScannerEnabled
    self.scannerDwellSeconds = Self.clampedScannerDwellSeconds(scannerDwellSeconds)
    self.scannerHoldSeconds = Self.clampedScannerHoldSeconds(scannerHoldSeconds)
    self.fmdxAudioStartupBufferSeconds = Self.clampedFMDXAudioStartupBufferSeconds(fmdxAudioStartupBufferSeconds)
    self.fmdxAudioMaxLatencySeconds = Self.clampedFMDXAudioMaxLatencySeconds(
      fmdxAudioMaxLatencySeconds,
      startupBufferSeconds: self.fmdxAudioStartupBufferSeconds
    )
    self.fmdxAudioPacketHoldSeconds = Self.clampedFMDXAudioPacketHoldSeconds(fmdxAudioPacketHoldSeconds)
    self.audioSuggestionScope = audioSuggestionScope
    self.tuningGestureDirection = tuningGestureDirection
    self.openReceiverAfterHistoryRestore = openReceiverAfterHistoryRestore
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    frequencyHz = try container.decodeIfPresent(Int.self, forKey: .frequencyHz) ?? Self.default.frequencyHz
    let rawTuneStepHz = try container.decodeIfPresent(Int.self, forKey: .tuneStepHz) ?? Self.default.tuneStepHz
    tuneStepHz = Self.normalizedTuneStep(rawTuneStepHz)
    let rawPreferredTuneStepHz = try container.decodeIfPresent(Int.self, forKey: .preferredTuneStepHz) ?? rawTuneStepHz
    preferredTuneStepHz = Self.normalizedTuneStep(rawPreferredTuneStepHz)
    mode = try container.decodeIfPresent(DemodulationMode.self, forKey: .mode) ?? Self.default.mode
    rfGain = try container.decodeIfPresent(Double.self, forKey: .rfGain) ?? Self.default.rfGain
    audioVolume = try container.decodeIfPresent(Double.self, forKey: .audioVolume) ?? Self.default.audioVolume
    audioMuted = try container.decodeIfPresent(Bool.self, forKey: .audioMuted) ?? Self.default.audioMuted
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
    dxNightModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .dxNightModeEnabled) ?? Self.default.dxNightModeEnabled
    autoFilterProfileEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoFilterProfileEnabled) ?? Self.default.autoFilterProfileEnabled
    adaptiveScannerEnabled = try container.decodeIfPresent(Bool.self, forKey: .adaptiveScannerEnabled) ?? Self.default.adaptiveScannerEnabled

    let rawScannerDwellSeconds = try container.decodeIfPresent(Double.self, forKey: .scannerDwellSeconds)
      ?? Self.default.scannerDwellSeconds
    scannerDwellSeconds = Self.clampedScannerDwellSeconds(rawScannerDwellSeconds)

    let rawScannerHoldSeconds = try container.decodeIfPresent(Double.self, forKey: .scannerHoldSeconds)
      ?? Self.default.scannerHoldSeconds
    scannerHoldSeconds = Self.clampedScannerHoldSeconds(rawScannerHoldSeconds)

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
    audioSuggestionScope = try container.decodeIfPresent(AudioSuggestionScope.self, forKey: .audioSuggestionScope)
      ?? Self.default.audioSuggestionScope
    tuningGestureDirection = try container.decodeIfPresent(TuningGestureDirection.self, forKey: .tuningGestureDirection)
      ?? Self.default.tuningGestureDirection
    openReceiverAfterHistoryRestore = try container.decodeIfPresent(Bool.self, forKey: .openReceiverAfterHistoryRestore)
      ?? Self.default.openReceiverAfterHistoryRestore
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(frequencyHz, forKey: .frequencyHz)
    try container.encode(tuneStepHz, forKey: .tuneStepHz)
    try container.encode(preferredTuneStepHz, forKey: .preferredTuneStepHz)
    try container.encode(mode, forKey: .mode)
    try container.encode(rfGain, forKey: .rfGain)
    try container.encode(audioVolume, forKey: .audioVolume)
    try container.encode(audioMuted, forKey: .audioMuted)
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
    try container.encode(dxNightModeEnabled, forKey: .dxNightModeEnabled)
    try container.encode(autoFilterProfileEnabled, forKey: .autoFilterProfileEnabled)
    try container.encode(adaptiveScannerEnabled, forKey: .adaptiveScannerEnabled)
    try container.encode(scannerDwellSeconds, forKey: .scannerDwellSeconds)
    try container.encode(scannerHoldSeconds, forKey: .scannerHoldSeconds)
    try container.encode(fmdxAudioStartupBufferSeconds, forKey: .fmdxAudioStartupBufferSeconds)
    try container.encode(fmdxAudioMaxLatencySeconds, forKey: .fmdxAudioMaxLatencySeconds)
    try container.encode(fmdxAudioPacketHoldSeconds, forKey: .fmdxAudioPacketHoldSeconds)
    try container.encode(audioSuggestionScope, forKey: .audioSuggestionScope)
    try container.encode(tuningGestureDirection, forKey: .tuningGestureDirection)
    try container.encode(openReceiverAfterHistoryRestore, forKey: .openReceiverAfterHistoryRestore)
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

  static let kiwiMinimumPassbandHz = 4

  static func kiwiPassbandLimitHz(sampleRateHz: Int?) -> Int {
    let halfRate = max((sampleRateHz ?? 0) / 2, 5_000)
    return max(halfRate, kiwiMinimumPassbandHz)
  }

  static func normalizedKiwiBandpass(
    _ bandpass: ReceiverBandpass,
    mode: DemodulationMode,
    sampleRateHz: Int?
  ) -> ReceiverBandpass {
    let normalizedMode = mode.normalized(for: .kiwiSDR)
    let limitHz = kiwiPassbandLimitHz(sampleRateHz: sampleRateHz)
    let fallback = normalizedMode.kiwiDefaultBandpass
    var lowCut = min(max(bandpass.lowCut, -limitHz), limitHz)
    var highCut = min(max(bandpass.highCut, -limitHz), limitHz)

    if lowCut >= highCut {
      lowCut = min(max(fallback.lowCut, -limitHz), limitHz)
      highCut = min(max(fallback.highCut, -limitHz), limitHz)
    }

    let minWidth = kiwiMinimumPassbandHz
    if (highCut - lowCut) < minWidth {
      let center = (lowCut + highCut) / 2
      lowCut = center - (minWidth / 2)
      highCut = lowCut + minWidth
      if lowCut < -limitHz {
        lowCut = -limitHz
        highCut = lowCut + minWidth
      }
      if highCut > limitHz {
        highCut = limitHz
        lowCut = highCut - minWidth
      }
    }

    if lowCut >= highCut {
      let fallbackLow = min(max(fallback.lowCut, -limitHz), limitHz)
      let fallbackHigh = min(max(fallback.highCut, -limitHz), limitHz)
      return ReceiverBandpass(lowCut: min(fallbackLow, fallbackHigh - minWidth), highCut: max(fallbackHigh, fallbackLow + minWidth))
    }

    return ReceiverBandpass(lowCut: lowCut, highCut: highCut)
  }

  func kiwiPassband(for mode: DemodulationMode, sampleRateHz: Int?) -> ReceiverBandpass {
    let normalizedMode = mode.normalized(for: .kiwiSDR)
    if let storedBandpass = kiwiPassbandsByMode[normalizedMode.rawValue] {
      return Self.normalizedKiwiBandpass(storedBandpass, mode: normalizedMode, sampleRateHz: sampleRateHz)
    }
    return Self.normalizedKiwiBandpass(
      normalizedMode.kiwiDefaultBandpass,
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
}
