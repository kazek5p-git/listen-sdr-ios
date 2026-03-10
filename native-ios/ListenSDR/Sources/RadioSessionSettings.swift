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

struct RadioSessionSettings: Codable, Equatable {
  var frequencyHz: Int
  var tuneStepHz: Int
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
  var kiwiWaterfallSpeed: Int
  var kiwiWaterfallZoom: Int
  var kiwiWaterfallMinDB: Int
  var kiwiWaterfallMaxDB: Int
  var showRdsErrorCounters: Bool
  var voiceOverRDSAnnouncementMode: VoiceOverRDSAnnouncementMode
  var shazamIntegrationEnabled: Bool
  var dxNightModeEnabled: Bool
  var autoFilterProfileEnabled: Bool
  var adaptiveScannerEnabled: Bool
  var scannerDwellSeconds: Double
  var scannerHoldSeconds: Double
  var fmdxAudioStartupBufferSeconds: Double
  var fmdxAudioMaxLatencySeconds: Double
  var fmdxAudioPacketHoldSeconds: Double

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
    kiwiWaterfallSpeed: 2,
    kiwiWaterfallZoom: 0,
    kiwiWaterfallMinDB: -145,
    kiwiWaterfallMaxDB: -20,
    showRdsErrorCounters: false,
    voiceOverRDSAnnouncementMode: .off,
    shazamIntegrationEnabled: false,
    dxNightModeEnabled: false,
    autoFilterProfileEnabled: false,
    adaptiveScannerEnabled: false,
    scannerDwellSeconds: 1.5,
    scannerHoldSeconds: 4.0,
    fmdxAudioStartupBufferSeconds: 0.55,
    fmdxAudioMaxLatencySeconds: 1.8,
    fmdxAudioPacketHoldSeconds: 0.14
  )

  private enum CodingKeys: String, CodingKey {
    case frequencyHz
    case tuneStepHz
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
    case kiwiWaterfallSpeed
    case kiwiWaterfallZoom
    case kiwiWaterfallMinDB
    case kiwiWaterfallMaxDB
    case showRdsErrorCounters
    case voiceOverRDSAnnouncementMode
    case voiceOverAnnouncesRDSChanges
    case shazamIntegrationEnabled
    case dxNightModeEnabled
    case autoFilterProfileEnabled
    case adaptiveScannerEnabled
    case scannerDwellSeconds
    case scannerHoldSeconds
    case fmdxAudioStartupBufferSeconds
    case fmdxAudioMaxLatencySeconds
    case fmdxAudioPacketHoldSeconds
  }

  init(
    frequencyHz: Int,
    tuneStepHz: Int,
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
    kiwiWaterfallSpeed: Int,
    kiwiWaterfallZoom: Int,
    kiwiWaterfallMinDB: Int,
    kiwiWaterfallMaxDB: Int,
    showRdsErrorCounters: Bool,
    voiceOverRDSAnnouncementMode: VoiceOverRDSAnnouncementMode,
    shazamIntegrationEnabled: Bool,
    dxNightModeEnabled: Bool,
    autoFilterProfileEnabled: Bool,
    adaptiveScannerEnabled: Bool,
    scannerDwellSeconds: Double,
    scannerHoldSeconds: Double,
    fmdxAudioStartupBufferSeconds: Double,
    fmdxAudioMaxLatencySeconds: Double,
    fmdxAudioPacketHoldSeconds: Double
  ) {
    self.frequencyHz = frequencyHz
    self.tuneStepHz = Self.normalizedTuneStep(tuneStepHz)
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
    self.kiwiWaterfallSpeed = Self.normalizedKiwiWaterfallSpeed(kiwiWaterfallSpeed)
    self.kiwiWaterfallZoom = Self.clampedKiwiWaterfallZoom(kiwiWaterfallZoom)
    self.kiwiWaterfallMinDB = Self.clampedKiwiWaterfallMinDB(kiwiWaterfallMinDB)
    self.kiwiWaterfallMaxDB = Self.clampedKiwiWaterfallMaxDB(kiwiWaterfallMaxDB)
    if self.kiwiWaterfallMaxDB <= self.kiwiWaterfallMinDB {
      self.kiwiWaterfallMaxDB = min(0, self.kiwiWaterfallMinDB + 10)
    }
    self.showRdsErrorCounters = showRdsErrorCounters
    self.voiceOverRDSAnnouncementMode = voiceOverRDSAnnouncementMode
    self.shazamIntegrationEnabled = shazamIntegrationEnabled
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
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    frequencyHz = try container.decodeIfPresent(Int.self, forKey: .frequencyHz) ?? Self.default.frequencyHz
    let rawTuneStepHz = try container.decodeIfPresent(Int.self, forKey: .tuneStepHz) ?? Self.default.tuneStepHz
    tuneStepHz = Self.normalizedTuneStep(rawTuneStepHz)
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

    let rawKiwiWaterfallSpeed = try container.decodeIfPresent(Int.self, forKey: .kiwiWaterfallSpeed)
      ?? Self.default.kiwiWaterfallSpeed
    kiwiWaterfallSpeed = Self.normalizedKiwiWaterfallSpeed(rawKiwiWaterfallSpeed)

    let rawKiwiWaterfallZoom = try container.decodeIfPresent(Int.self, forKey: .kiwiWaterfallZoom)
      ?? Self.default.kiwiWaterfallZoom
    kiwiWaterfallZoom = Self.clampedKiwiWaterfallZoom(rawKiwiWaterfallZoom)

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
    shazamIntegrationEnabled = try container.decodeIfPresent(Bool.self, forKey: .shazamIntegrationEnabled)
      ?? Self.default.shazamIntegrationEnabled
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
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(frequencyHz, forKey: .frequencyHz)
    try container.encode(tuneStepHz, forKey: .tuneStepHz)
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
    try container.encode(kiwiWaterfallSpeed, forKey: .kiwiWaterfallSpeed)
    try container.encode(kiwiWaterfallZoom, forKey: .kiwiWaterfallZoom)
    try container.encode(kiwiWaterfallMinDB, forKey: .kiwiWaterfallMinDB)
    try container.encode(kiwiWaterfallMaxDB, forKey: .kiwiWaterfallMaxDB)
    try container.encode(showRdsErrorCounters, forKey: .showRdsErrorCounters)
    try container.encode(voiceOverRDSAnnouncementMode, forKey: .voiceOverRDSAnnouncementMode)
    try container.encode(shazamIntegrationEnabled, forKey: .shazamIntegrationEnabled)
    try container.encode(dxNightModeEnabled, forKey: .dxNightModeEnabled)
    try container.encode(autoFilterProfileEnabled, forKey: .autoFilterProfileEnabled)
    try container.encode(adaptiveScannerEnabled, forKey: .adaptiveScannerEnabled)
    try container.encode(scannerDwellSeconds, forKey: .scannerDwellSeconds)
    try container.encode(scannerHoldSeconds, forKey: .scannerHoldSeconds)
    try container.encode(fmdxAudioStartupBufferSeconds, forKey: .fmdxAudioStartupBufferSeconds)
    try container.encode(fmdxAudioMaxLatencySeconds, forKey: .fmdxAudioMaxLatencySeconds)
    try container.encode(fmdxAudioPacketHoldSeconds, forKey: .fmdxAudioPacketHoldSeconds)
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

  static func normalizedKiwiWaterfallSpeed(_ value: Int) -> Int {
    let options = [1, 2, 4, 8]
    if options.contains(value) {
      return value
    }
    return options.min(by: { abs($0 - value) < abs($1 - value) }) ?? Self.default.kiwiWaterfallSpeed
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
