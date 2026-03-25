import Foundation

public enum KiwiNoiseBlankerAlgorithm: Int, CaseIterable, Codable, Identifiable, Sendable {
  case off = 0
  case standard = 1
  case wild = 2

  public var id: Int { rawValue }
}

public enum KiwiNoiseFilterAlgorithm: Int, CaseIterable, Codable, Identifiable, Sendable {
  case off = 0
  case wdsp = 1
  case original = 2
  case spectral = 3

  public var id: Int { rawValue }
}
