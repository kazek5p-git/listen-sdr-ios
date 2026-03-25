import XCTest
@testable import ListenSDRCore

final class KiwiPassbandCoreTests: XCTestCase {
  func testNormalizedBandpassMatchesCanonicalFixtures() throws {
    let fixture: KiwiPassbandCoreFixtureSet = try FixtureLoader.load(
      "kiwi-passband-core-cases.json"
    )

    for testCase in fixture.normalizedCases {
      XCTAssertEqual(
        testCase.expectedBandpass,
        KiwiPassbandCore.normalizedBandpass(
          testCase.bandpass,
          mode: testCase.mode,
          sampleRateHz: testCase.sampleRateHz
        ),
        testCase.label
      )
    }
  }

  func testResolvedBandpassMatchesCanonicalFixtures() throws {
    let fixture: KiwiPassbandCoreFixtureSet = try FixtureLoader.load(
      "kiwi-passband-core-cases.json"
    )

    for testCase in fixture.resolvedCases {
      XCTAssertEqual(
        testCase.expectedBandpass,
        KiwiPassbandCore.resolvedBandpass(
          storedBandpass: testCase.storedBandpass,
          mode: testCase.mode,
          sampleRateHz: testCase.sampleRateHz
        ),
        testCase.label
      )
    }
  }
}

private struct KiwiPassbandCoreFixtureSet: Decodable {
  let normalizedCases: [KiwiPassbandCoreNormalizationFixtureCase]
  let resolvedCases: [KiwiPassbandCoreResolvedFixtureCase]
}

private struct KiwiPassbandCoreNormalizationFixtureCase: Decodable {
  let label: String
  let mode: DemodulationMode
  let bandpass: ReceiverBandpass
  let sampleRateHz: Int?
  let expectedBandpass: ReceiverBandpass
}

private struct KiwiPassbandCoreResolvedFixtureCase: Decodable {
  let label: String
  let mode: DemodulationMode
  let storedBandpass: ReceiverBandpass?
  let sampleRateHz: Int?
  let expectedBandpass: ReceiverBandpass
}
