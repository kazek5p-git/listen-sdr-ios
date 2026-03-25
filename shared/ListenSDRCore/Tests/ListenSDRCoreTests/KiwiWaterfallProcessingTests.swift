import XCTest
@testable import ListenSDRCore

final class KiwiWaterfallProcessingTests: XCTestCase {
  func testCanonicalFixturesRemainStable() throws {
    let fixture: KiwiProcessingFixtureSet = try FixtureLoader.load("kiwi-processing-cases.json")

    for entry in fixture.commandCases {
      XCTAssertEqual(
        try KiwiWaterfallInterpolation(fixtureValue: entry.interpolation)
          .commandValue(cicCompensation: entry.cicCompensation),
        entry.expectedCommandValue,
        entry.label
      )
    }

    for entry in fixture.rawValueCases {
      switch entry.kind {
      case "waterfallRate":
        XCTAssertEqual(try KiwiWaterfallRate(fixtureValue: entry.name).rawValue, entry.expectedRawValue, entry.label)
      case "windowFunction":
        XCTAssertEqual(
          try KiwiWaterfallWindowFunction(fixtureValue: entry.name).rawValue,
          entry.expectedRawValue,
          entry.label
        )
      case "noiseBlanker":
        XCTAssertEqual(
          try KiwiNoiseBlankerAlgorithm(fixtureValue: entry.name).rawValue,
          entry.expectedRawValue,
          entry.label
        )
      case "noiseFilter":
        XCTAssertEqual(
          try KiwiNoiseFilterAlgorithm(fixtureValue: entry.name).rawValue,
          entry.expectedRawValue,
          entry.label
        )
      case "interpolation":
        XCTAssertEqual(
          try KiwiWaterfallInterpolation(fixtureValue: entry.name).rawValue,
          entry.expectedRawValue,
          entry.label
        )
      default:
        throw FixtureError.invalidFixtureValue("Unknown Kiwi processing fixture kind: \(entry.kind)")
      }
    }
  }

  func testInterpolationCommandValueAddsCICOffset() {
    XCTAssertEqual(KiwiWaterfallInterpolation.dropSamples.commandValue(cicCompensation: false), 3)
    XCTAssertEqual(KiwiWaterfallInterpolation.dropSamples.commandValue(cicCompensation: true), 13)
    XCTAssertEqual(KiwiWaterfallInterpolation.cma.commandValue(cicCompensation: true), 14)
  }

  func testRawValuesRemainStableForSerialization() {
    XCTAssertEqual(KiwiWaterfallRate.medium.rawValue, 3)
    XCTAssertEqual(KiwiWaterfallWindowFunction.blackmanHarris.rawValue, 2)
    XCTAssertEqual(KiwiNoiseBlankerAlgorithm.wild.rawValue, 2)
    XCTAssertEqual(KiwiNoiseFilterAlgorithm.spectral.rawValue, 3)
  }
}

private struct KiwiProcessingFixtureSet: Decodable {
  let commandCases: [CommandCase]
  let rawValueCases: [RawValueCase]

  struct CommandCase: Decodable {
    let label: String
    let interpolation: String
    let cicCompensation: Bool
    let expectedCommandValue: Int
  }

  struct RawValueCase: Decodable {
    let label: String
    let kind: String
    let name: String
    let expectedRawValue: Int
  }
}

private extension KiwiWaterfallInterpolation {
  init(fixtureValue: String) throws {
    switch fixtureValue {
    case "max":
      self = .max
    case "min":
      self = .min
    case "last":
      self = .last
    case "dropSamples":
      self = .dropSamples
    case "cma":
      self = .cma
    default:
      throw FixtureError.invalidFixtureValue("Unknown Kiwi interpolation fixture: \(fixtureValue)")
    }
  }
}

private extension KiwiWaterfallRate {
  init(fixtureValue: String) throws {
    switch fixtureValue {
    case "off":
      self = .off
    case "oneHertz":
      self = .oneHertz
    case "slow":
      self = .slow
    case "medium":
      self = .medium
    case "fast":
      self = .fast
    default:
      throw FixtureError.invalidFixtureValue("Unknown Kiwi waterfall rate fixture: \(fixtureValue)")
    }
  }
}

private extension KiwiWaterfallWindowFunction {
  init(fixtureValue: String) throws {
    switch fixtureValue {
    case "hanning":
      self = .hanning
    case "hamming":
      self = .hamming
    case "blackmanHarris":
      self = .blackmanHarris
    case "none":
      self = .none
    default:
      throw FixtureError.invalidFixtureValue("Unknown Kiwi window function fixture: \(fixtureValue)")
    }
  }
}

private extension KiwiNoiseBlankerAlgorithm {
  init(fixtureValue: String) throws {
    switch fixtureValue {
    case "off":
      self = .off
    case "standard":
      self = .standard
    case "wild":
      self = .wild
    default:
      throw FixtureError.invalidFixtureValue("Unknown Kiwi noise blanker fixture: \(fixtureValue)")
    }
  }
}

private extension KiwiNoiseFilterAlgorithm {
  init(fixtureValue: String) throws {
    switch fixtureValue {
    case "off":
      self = .off
    case "wdsp":
      self = .wdsp
    case "original":
      self = .original
    case "spectral":
      self = .spectral
    default:
      throw FixtureError.invalidFixtureValue("Unknown Kiwi noise filter fixture: \(fixtureValue)")
    }
  }
}
