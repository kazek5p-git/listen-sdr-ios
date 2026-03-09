import Foundation

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
  var voiceOverAnnouncesRDSChanges: Bool
  var shazamIntegrationEnabled: Bool
  var dxNightModeEnabled: Bool
  var autoFilterProfileEnabled: Bool
  var adaptiveScannerEnabled: Bool
  var scannerDwellSeconds: Double
  var scannerHoldSeconds: Double

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
    voiceOverAnnouncesRDSChanges: false,
    shazamIntegrationEnabled: false,
    dxNightModeEnabled: false,
    autoFilterProfileEnabled: false,
    adaptiveScannerEnabled: false,
    scannerDwellSeconds: 1.5,
    scannerHoldSeconds: 4.0
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
    case voiceOverAnnouncesRDSChanges
    case shazamIntegrationEnabled
    case dxNightModeEnabled
    case autoFilterProfileEnabled
    case adaptiveScannerEnabled
    case scannerDwellSeconds
    case scannerHoldSeconds
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
    voiceOverAnnouncesRDSChanges: Bool,
    shazamIntegrationEnabled: Bool,
    dxNightModeEnabled: Bool,
    autoFilterProfileEnabled: Bool,
    adaptiveScannerEnabled: Bool,
    scannerDwellSeconds: Double,
    scannerHoldSeconds: Double
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
    self.voiceOverAnnouncesRDSChanges = voiceOverAnnouncesRDSChanges
    self.shazamIntegrationEnabled = shazamIntegrationEnabled
    self.dxNightModeEnabled = dxNightModeEnabled
    self.autoFilterProfileEnabled = autoFilterProfileEnabled
    self.adaptiveScannerEnabled = adaptiveScannerEnabled
    self.scannerDwellSeconds = Self.clampedScannerDwellSeconds(scannerDwellSeconds)
    self.scannerHoldSeconds = Self.clampedScannerHoldSeconds(scannerHoldSeconds)
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
    voiceOverAnnouncesRDSChanges = try container.decodeIfPresent(Bool.self, forKey: .voiceOverAnnouncesRDSChanges)
      ?? Self.default.voiceOverAnnouncesRDSChanges
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
}
