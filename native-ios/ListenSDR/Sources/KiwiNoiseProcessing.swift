import Foundation

enum KiwiNoiseBlankerAlgorithm: Int, CaseIterable, Codable, Identifiable {
  case off = 0
  case standard = 1
  case wild = 2

  var id: Int { rawValue }
}

enum KiwiNoiseFilterAlgorithm: Int, CaseIterable, Codable, Identifiable {
  case off = 0
  case wdsp = 1
  case original = 2
  case spectral = 3

  var id: Int { rawValue }
}
