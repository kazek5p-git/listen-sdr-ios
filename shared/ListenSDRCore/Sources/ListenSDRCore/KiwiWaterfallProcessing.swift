import Foundation

public enum KiwiWaterfallRate: Int, CaseIterable, Identifiable, Codable, Sendable {
  case off = 0
  case oneHertz = 1
  case slow = 2
  case medium = 3
  case fast = 4

  public var id: Int { rawValue }
}

public enum KiwiWaterfallWindowFunction: Int, CaseIterable, Identifiable, Codable, Sendable {
  case hanning = 0
  case hamming = 1
  case blackmanHarris = 2
  case none = 3

  public var id: Int { rawValue }
}

public enum KiwiWaterfallInterpolation: Int, CaseIterable, Identifiable, Codable, Sendable {
  case max = 0
  case min = 1
  case last = 2
  case dropSamples = 3
  case cma = 4

  public var id: Int { rawValue }

  public func commandValue(cicCompensation: Bool) -> Int {
    rawValue + (cicCompensation ? 10 : 0)
  }
}
