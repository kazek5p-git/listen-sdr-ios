import Foundation

struct RadioSessionSettings: Codable, Equatable {
  var frequencyHz: Int
  var tuneStepHz: Int
  var mode: DemodulationMode
  var rfGain: Double
  var audioVolume: Double
  var audioMuted: Bool
  var agcEnabled: Bool
  var noiseReductionEnabled: Bool
  var squelchEnabled: Bool

  static let supportedTuneStepsHz: [Int] = [10, 50, 100, 500, 1_000, 5_000, 9_000, 10_000, 12_500, 25_000]

  static let `default` = RadioSessionSettings(
    frequencyHz: 7_050_000,
    tuneStepHz: 100,
    mode: .am,
    rfGain: 30,
    audioVolume: 0.85,
    audioMuted: false,
    agcEnabled: true,
    noiseReductionEnabled: false,
    squelchEnabled: false
  )

  private enum CodingKeys: String, CodingKey {
    case frequencyHz
    case tuneStepHz
    case mode
    case rfGain
    case audioVolume
    case audioMuted
    case agcEnabled
    case noiseReductionEnabled
    case squelchEnabled
  }

  init(
    frequencyHz: Int,
    tuneStepHz: Int,
    mode: DemodulationMode,
    rfGain: Double,
    audioVolume: Double,
    audioMuted: Bool,
    agcEnabled: Bool,
    noiseReductionEnabled: Bool,
    squelchEnabled: Bool
  ) {
    self.frequencyHz = frequencyHz
    self.tuneStepHz = Self.normalizedTuneStep(tuneStepHz)
    self.mode = mode
    self.rfGain = rfGain
    self.audioVolume = audioVolume
    self.audioMuted = audioMuted
    self.agcEnabled = agcEnabled
    self.noiseReductionEnabled = noiseReductionEnabled
    self.squelchEnabled = squelchEnabled
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
    noiseReductionEnabled = try container.decodeIfPresent(Bool.self, forKey: .noiseReductionEnabled) ?? Self.default.noiseReductionEnabled
    squelchEnabled = try container.decodeIfPresent(Bool.self, forKey: .squelchEnabled) ?? Self.default.squelchEnabled
  }

  static func normalizedTuneStep(_ value: Int) -> Int {
    if supportedTuneStepsHz.contains(value) {
      return value
    }
    return supportedTuneStepsHz.min(by: { abs($0 - value) < abs($1 - value) }) ?? Self.default.tuneStepHz
  }
}
