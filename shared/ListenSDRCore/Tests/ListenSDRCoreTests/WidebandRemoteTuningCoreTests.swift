import XCTest
@testable import ListenSDRCore

final class WidebandRemoteTuningCoreTests: XCTestCase {
  func testOpenWebRXTuningMatchesCanonicalFixtures() throws {
    let fixture: WidebandRemoteTuningCoreFixtureSet = try FixtureLoader.load(
      "wideband-remote-tuning-core-cases.json"
    )

    for testCase in fixture.openWebRXCases {
      let result = WidebandRemoteTuningCore.synchronizeOpenWebRX(
        state: testCase.currentState,
        reportedFrequencyHz: testCase.reportedFrequencyHz,
        reportedMode: testCase.reportedMode,
        bandName: testCase.bandName,
        bandTags: testCase.bandTags
      )

      XCTAssertEqual(testCase.expectedState, result.state, testCase.label)
      XCTAssertEqual(testCase.expectedStatusSummary, result.statusSummary, testCase.label)
    }
  }

  func testKiwiTuningMatchesCanonicalFixtures() throws {
    let fixture: WidebandRemoteTuningCoreFixtureSet = try FixtureLoader.load(
      "wideband-remote-tuning-core-cases.json"
    )

    for testCase in fixture.kiwiCases {
      let result = WidebandRemoteTuningCore.synchronizeKiwi(
        state: testCase.currentState,
        reportedFrequencyHz: testCase.reportedFrequencyHz,
        reportedMode: testCase.reportedMode,
        reportedBandName: testCase.reportedBandName,
        currentPassband: testCase.currentPassband,
        reportedPassband: testCase.reportedPassband,
        sampleRateHz: testCase.sampleRateHz
      )

      XCTAssertEqual(testCase.expectedState, result.state, testCase.label)
      XCTAssertEqual(testCase.expectedNormalizedBandName, result.normalizedBandName, testCase.label)
      XCTAssertEqual(testCase.expectedResolvedPassband, result.resolvedKiwiPassband, testCase.label)
      XCTAssertEqual(testCase.expectedStatusSummary, result.statusSummary, testCase.label)
    }
  }
}

private struct WidebandRemoteTuningCoreFixtureSet: Decodable {
  let openWebRXCases: [OpenWebRXWidebandRemoteTuningFixtureCase]
  let kiwiCases: [KiwiWidebandRemoteTuningFixtureCase]
}

private struct OpenWebRXWidebandRemoteTuningFixtureCase: Decodable {
  let label: String
  let currentState: WidebandRemoteTuningState
  let reportedFrequencyHz: Int
  let reportedMode: DemodulationMode?
  let bandName: String?
  let bandTags: [String]
  let expectedState: WidebandRemoteTuningState
  let expectedStatusSummary: String
}

private struct KiwiWidebandRemoteTuningFixtureCase: Decodable {
  let label: String
  let currentState: WidebandRemoteTuningState
  let reportedFrequencyHz: Int
  let reportedMode: DemodulationMode?
  let reportedBandName: String?
  let currentPassband: ReceiverBandpass
  let reportedPassband: ReceiverBandpass?
  let sampleRateHz: Int?
  let expectedState: WidebandRemoteTuningState
  let expectedNormalizedBandName: String?
  let expectedResolvedPassband: ReceiverBandpass
  let expectedStatusSummary: String
}
