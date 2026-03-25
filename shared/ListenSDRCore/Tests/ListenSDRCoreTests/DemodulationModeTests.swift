import XCTest
@testable import ListenSDRCore

final class DemodulationModeTests: XCTestCase {
  func testCanonicalFixturesRemainStable() throws {
    let fixture: DemodulationModeFixtureSet = try FixtureLoader.load("demodulation-mode-cases.json")

    for entry in fixture.normalizationCases {
      let mode = try DemodulationMode(fixtureValue: entry.mode)
      let backend = try SDRBackend(fixtureValue: entry.backend)

      XCTAssertEqual(mode.normalized(for: backend), try DemodulationMode(fixtureValue: entry.expectedMode), entry.label)
    }

    for entry in fixture.protocolCases {
      let mode = try DemodulationMode(fixtureValue: entry.mode)
      let backend = try SDRBackend(fixtureValue: entry.backend)

      switch backend {
      case .kiwiSDR:
        XCTAssertEqual(mode.kiwiProtocolMode, entry.expectedProtocolMode, entry.label)
        XCTAssertEqual(mode.kiwiDefaultBandpass, entry.expectedBandpass.bandpass, entry.label)
      case .openWebRX:
        XCTAssertEqual(mode.openWebRXProtocolMode, entry.expectedProtocolMode, entry.label)
        XCTAssertEqual(mode.openWebRXDefaultBandpass, entry.expectedBandpass.bandpass, entry.label)
      case .fmDxWebserver:
        XCTFail("Unsupported protocol fixture backend for \(entry.label)")
      }
    }

    for entry in fixture.parsingCases {
      let expectedMode = try entry.expectedMode.map(DemodulationMode.init(fixtureValue:))
      switch entry.source {
      case "kiwi":
        XCTAssertEqual(DemodulationMode.fromKiwi(entry.rawValue), expectedMode, entry.label)
      case "openWebRX":
        XCTAssertEqual(DemodulationMode.fromOpenWebRX(entry.rawValue), expectedMode, entry.label)
      default:
        throw FixtureError.invalidFixtureValue("Unknown demodulation parsing source fixture: \(entry.source)")
      }
    }

    for entry in fixture.fineTuningCases {
      XCTAssertEqual(
        try DemodulationMode(fixtureValue: entry.mode).isFineTuningMode,
        entry.expected,
        entry.label
      )
    }
  }

  func testNormalizationMatchesBackendRules() {
    XCTAssertEqual(DemodulationMode.usn.normalized(for: .openWebRX), .usb)
    XCTAssertEqual(DemodulationMode.fm.normalized(for: .kiwiSDR), .nfm)
    XCTAssertEqual(DemodulationMode.usb.normalized(for: .fmDxWebserver), .fm)
    XCTAssertEqual(DemodulationMode.am.normalized(for: .fmDxWebserver), .am)
  }

  func testProtocolModesAndBandpassesUseNormalizedMode() {
    XCTAssertEqual(DemodulationMode.fm.kiwiProtocolMode, "nbfm")
    XCTAssertEqual(DemodulationMode.usn.openWebRXProtocolMode, "usb")
    XCTAssertEqual(
      DemodulationMode.fm.kiwiDefaultBandpass,
      ReceiverBandpass(lowCut: -6_000, highCut: 6_000)
    )
    XCTAssertEqual(
      DemodulationMode.fm.openWebRXDefaultBandpass,
      ReceiverBandpass(lowCut: -75_000, highCut: 75_000)
    )
  }

  func testModeParsingMatchesExpectedAliases() {
    XCTAssertEqual(DemodulationMode.fromKiwi("wfm"), .nfm)
    XCTAssertEqual(DemodulationMode.fromKiwi("qam"), .qam)
    XCTAssertEqual(DemodulationMode.fromOpenWebRX("wfm"), .fm)
    XCTAssertNil(DemodulationMode.fromOpenWebRX("drm"))
  }

  func testFineTuningModesRemainExplicit() {
    XCTAssertTrue(DemodulationMode.cw.isFineTuningMode)
    XCTAssertTrue(DemodulationMode.usb.isFineTuningMode)
    XCTAssertFalse(DemodulationMode.am.isFineTuningMode)
    XCTAssertFalse(DemodulationMode.fm.isFineTuningMode)
  }
}

private struct DemodulationModeFixtureSet: Decodable {
  let normalizationCases: [NormalizationCase]
  let protocolCases: [ProtocolCase]
  let parsingCases: [ParsingCase]
  let fineTuningCases: [FineTuningCase]

  struct NormalizationCase: Decodable {
    let label: String
    let mode: String
    let backend: String
    let expectedMode: String
  }

  struct ProtocolCase: Decodable {
    let label: String
    let mode: String
    let backend: String
    let expectedProtocolMode: String
    let expectedBandpass: BandpassFixture
  }

  struct ParsingCase: Decodable {
    let label: String
    let source: String
    let rawValue: String
    let expectedMode: String?
  }

  struct FineTuningCase: Decodable {
    let label: String
    let mode: String
    let expected: Bool
  }

  struct BandpassFixture: Decodable {
    let lowCut: Int
    let highCut: Int

    var bandpass: ReceiverBandpass {
      ReceiverBandpass(lowCut: lowCut, highCut: highCut)
    }
  }
}
