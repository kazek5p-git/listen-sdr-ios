import XCTest
@testable import ListenSDRCore

final class BackendStatusSummaryCoreTests: XCTestCase {
  func testSummariesMatchCanonicalFixtures() throws {
    let fixture: BackendStatusSummaryCoreFixtureSet = try FixtureLoader.load(
      "backend-status-summary-core-cases.json"
    )

    for testCase in fixture.cases {
      let summary: String
      switch testCase.backend {
      case .openWebRX:
        summary = BackendStatusSummaryCore.openWebRXSummary(
          frequencyHz: testCase.frequencyHz,
          mode: testCase.mode,
          bandName: testCase.bandName
        )
      case .kiwiSDR:
        summary = BackendStatusSummaryCore.kiwiSummary(
          frequencyHz: testCase.frequencyHz,
          mode: testCase.mode,
          reportedBandName: testCase.bandName
        )
      case .fmDxWebserver:
        XCTFail("Unsupported backend for backend status summary fixture: \(testCase.backend)")
        continue
      }

      XCTAssertEqual(testCase.expectedSummary, summary, testCase.label)
    }
  }

  func testBandNameNormalizationMatchesCanonicalFixtures() throws {
    let fixture: BackendStatusSummaryCoreFixtureSet = try FixtureLoader.load(
      "backend-status-summary-core-cases.json"
    )

    for testCase in fixture.cases {
      XCTAssertEqual(
        testCase.expectedNormalizedBandName,
        BackendStatusSummaryCore.normalizedBandName(testCase.bandName),
        testCase.label
      )
    }
  }
}

private struct BackendStatusSummaryCoreFixtureSet: Decodable {
  let cases: [BackendStatusSummaryCoreFixtureCase]
}

private struct BackendStatusSummaryCoreFixtureCase: Decodable {
  let label: String
  let backend: SDRBackend
  let frequencyHz: Int
  let mode: DemodulationMode?
  let bandName: String?
  let expectedSummary: String
  let expectedNormalizedBandName: String?
}
